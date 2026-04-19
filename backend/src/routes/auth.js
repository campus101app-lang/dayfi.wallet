import express from 'express';
import { body, validationResult } from 'express-validator';
import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import { sendOTP, sendWelcomeEmail } from '../services/emailService.js';
import {
  createStellarWallet,
  getMnemonic,
  markAsBackedUp,
  fundNewUserWallet,
  addAllTrustlines,
  setupUserTrustlines,
} from '../services/walletService.js';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();
const prisma = new PrismaClient();

function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// POST /api/auth/send-otp
router.post('/send-otp', [
  body('email').isEmail().normalizeEmail(),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { email } = req.body;
  try {
    let user = await prisma.user.findUnique({ where: { email } });
    const isNewUser = !user;
    const otp = generateOTP();
    const otpExpiry = new Date(Date.now() + 10 * 60 * 1000);

    if (!user) {
      user = await prisma.user.create({
        data: { email, username: `user_${Date.now()}`, otpCode: otp, otpExpiry, otpAttempts: 0 },
      });
    } else {
      await prisma.user.update({
        where: { email },
        data: { otpCode: otp, otpExpiry, otpAttempts: 0 },
      });
    }

    try { await sendOTP(email, otp, isNewUser); }
    catch (err) { console.warn('Email delivery failed:', err.message); }

    console.log(`\n🔑 OTP for ${email}: ${otp}\n`);

    res.json({
      success: true, isNewUser,
      message: `OTP sent to ${email}`,
      ...(process.env.NODE_ENV === 'development' && { devOtp: otp }),
    });
  } catch (err) {
    console.error('Send OTP error:', err);
    res.status(500).json({ error: 'Failed to send OTP.' });
  }
});

// POST /api/auth/verify-otp
router.post('/verify-otp', [
  body('email').isEmail().normalizeEmail(),
  body('otp').isLength({ min: 6, max: 6 }).isNumeric(),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { email, otp } = req.body;
  try {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) return res.status(404).json({ error: 'User not found' });

    if (user.otpAttempts >= 5)
      return res.status(429).json({ error: 'Too many attempts. Request a new code.' });
    if (!user.otpExpiry || new Date() > user.otpExpiry)
      return res.status(400).json({ error: 'OTP expired.' });
    if (user.otpCode !== otp) {
      await prisma.user.update({ where: { email }, data: { otpAttempts: { increment: 1 } } });
      return res.status(400).json({ error: 'Invalid code.', attemptsLeft: 5 - (user.otpAttempts + 1) });
    }

    const needsUsername = user.username.startsWith('user_');
    await prisma.user.update({
      where: { email },
      data: { otpCode: null, otpExpiry: null, otpAttempts: 0, isVerified: true },
    });

    if (!needsUsername && user.stellarPublicKey) {
      const token = jwt.sign(
        { userId: user.id, email: user.email },
        process.env.JWT_SECRET,
        { expiresIn: process.env.JWT_EXPIRES_IN || '30d' }
      );
      return res.json({
        success: true, step: 'complete', token,
        user: {
          id: user.id, email: user.email,
          username: user.username,
          dayfiUsername: `${user.username}@dayfi.me`,
          stellarPublicKey: user.stellarPublicKey,
          isBackedUp: user.isBackedUp,
        },
      });
    }

    const setupToken = jwt.sign(
      { userId: user.id, email: user.email, setupMode: true },
      process.env.JWT_SECRET,
      { expiresIn: '30m' }
    );
    res.json({ success: true, step: 'setup_username', setupToken, userId: user.id });
  } catch (err) {
    console.error('Verify OTP error:', err);
    res.status(500).json({ error: 'Verification failed.' });
  }
});

// POST /api/auth/setup-username
router.post('/setup-username', [
  body('username').trim().isLength({ min: 3, max: 30 }).matches(/^[a-zA-Z0-9_]+$/),
  body('setupToken').notEmpty(),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { username, setupToken } = req.body;
  try {
    let decoded;
    try { decoded = jwt.verify(setupToken, process.env.JWT_SECRET); }
    catch { return res.status(401).json({ error: 'Invalid or expired setup token' }); }

    if (!decoded.setupMode) return res.status(401).json({ error: 'Invalid token' });

    const lowerUsername = username.toLowerCase();
    const existing = await prisma.user.findUnique({ where: { username: lowerUsername } });
    if (existing && existing.id !== decoded.userId)
      return res.status(409).json({ error: 'Username already taken.' });

    await prisma.user.update({
      where: { id: decoded.userId },
      data: { username: lowerUsername },
    });

    console.log(`\n⚙️  Creating Stellar wallet for @${lowerUsername}...`);
    const { publicKey, encryptedSecretKey, encryptedMnemonic } = await createStellarWallet();

    await prisma.user.update({
      where: { id: decoded.userId },
      data: { stellarPublicKey: publicKey, stellarSecretKey: encryptedSecretKey, encryptedMnemonic },
    });

    console.log(`✅ Wallet ready: ${publicKey}`);

    // ✅ decoded.userId exists here — no 'user' needed yet
    await fundNewUserWallet(publicKey, decoded.userId);

    // ✅ single DB fetch at the end, used for everything below
    const user = await prisma.user.findUnique({ where: { id: decoded.userId } });

    // trustlines already handled inside createStellarWallet() for testnet
    // only needed if you want to re-run it explicitly on mainnet
    await setupUserTrustlines(user);

    const token = jwt.sign(
      { userId: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '30d' }
    );

    try { await sendWelcomeEmail(user.email, user.username); }
    catch (err) { console.warn('⚠️  Welcome email failed:', err.message); }

    res.json({
      success: true, token,
      user: {
        id: user.id, email: user.email,
        username: user.username,
        dayfiUsername: `${user.username}@dayfi.me`,
        stellarPublicKey: user.stellarPublicKey,
        isBackedUp: user.isBackedUp,
      },
    });
  } catch (err) {
    console.error('Setup username error:', err);
    res.status(500).json({ error: 'Setup failed.' });
  }
});

// GET /api/auth/check-username/:username
router.get('/check-username/:username', async (req, res) => {
  const lower = req.params.username.toLowerCase().trim();
  if (!/^[a-zA-Z0-9_]{3,30}$/.test(lower))
    return res.json({ available: false, reason: 'Invalid format' });

  const reserved = ['admin', 'support', 'dayfi', 'help', 'system', 'api',
    'app', 'wallet', 'pay', 'send', 'receive', 'swap', 'buy', 'sell'];
  if (reserved.includes(lower))
    return res.json({ available: false, reason: 'Reserved username' });

  const existing = await prisma.user.findUnique({ where: { username: lower } });
  res.json({ available: !existing, username: lower });
});

// GET /api/auth/mnemonic — returns 12 words (Face ID verified on client)
router.get('/mnemonic', authenticate, async (req, res) => {
  try {
    const mnemonic = await getMnemonic(req.user.id);
    const words    = mnemonic.split(' ');
    res.json({ words });
  } catch (err) {
    res.status(404).json({ error: 'Recovery phrase not found' });
  }
});

// POST /api/auth/mark-backed-up
router.post('/mark-backed-up', authenticate, async (req, res) => {
  try {
    await markAsBackedUp(req.user.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/auth/refresh
router.post('/refresh', async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(401).json({ error: 'Token required' });
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user    = await prisma.user.findUnique({ where: { id: decoded.userId } });
    if (!user) return res.status(404).json({ error: 'User not found' });
    const newToken = jwt.sign(
      { userId: user.id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '30d' }
    );
    res.json({ token: newToken });
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
});

export default router;