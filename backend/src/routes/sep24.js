// src/routes/sep24.js
// SEP-24: Hosted Deposit and Withdrawal
// https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0024.md

import express from 'express';
import jwt from 'jsonwebtoken';
import { PrismaClient } from '@prisma/client';
import { v4 as uuidv4 } from 'uuid';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();
const prisma = new PrismaClient();

const HOME_DOMAIN = process.env.HOME_DOMAIN || 'dayfi.me';
const SUPPORTED_ASSETS = ['USDC', 'BTC', 'GOLD'];

// Middleware: accept either our JWT or a SEP-10 JWT
function sep10Auth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(403).json({ error: 'Missing authentication token' });
  }
  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    // SEP-10 token has 'sub' = Stellar address; our token has 'userId'
    req.stellarAccount = decoded.sub || null;
    req.userId = decoded.userId || null;
    next();
  } catch {
    return res.status(403).json({ error: 'Invalid token' });
  }
}

// GET /sep24/info
// Lists supported assets and their deposit/withdraw capabilities
router.get('/info', (req, res) => {
  const assetInfo = (assetCode) => ({
    enabled: true,
    min_amount: assetCode === 'BTC' ? 0.0001 : 1,
    max_amount: assetCode === 'BTC' ? 1 : 100000,
    fee_fixed: assetCode === 'BTC' ? 0.0001 : 0.5,
    fee_percent: 0.1,
  });

  res.json({
    deposit: {
      USDC: assetInfo('USDC'),
      BTC:  assetInfo('BTC'),
      GOLD: assetInfo('GOLD'),
    },
    withdraw: {
      USDC: assetInfo('USDC'),
      BTC:  assetInfo('BTC'),
      GOLD: assetInfo('GOLD'),
    },
    fee: { enabled: true, authentication_required: true },
    features: {
      account_creation: true,
      claimable_balances: false,
    },
  });
});

// POST /sep24/transactions/deposit/interactive
// Initiates a deposit — returns a URL for the hosted flow
router.post('/transactions/deposit/interactive', sep10Auth, async (req, res) => {
  const { asset_code, account, amount, memo, memo_type, lang } = req.body;

  if (!asset_code || !SUPPORTED_ASSETS.includes(asset_code)) {
    return res.status(400).json({ error: `Unsupported asset: ${asset_code}` });
  }

  const stellarAccount = account || req.stellarAccount;
  if (!stellarAccount) {
    return res.status(400).json({ error: 'account required' });
  }

  try {
    // Create a pending transaction record
    const txId = uuidv4();

    // Find user by stellar address
    const user = await prisma.user.findFirst({
      where: { stellarPublicKey: stellarAccount }
    });

    if (user) {
      await prisma.transaction.create({
        data: {
          id: txId,
          userId: user.id,
          type: 'receive',
          status: 'pending',
          amount: parseFloat(amount) || 0,
          asset: asset_code,
          network: 'stellar',
          fromAddress: 'pending',
          toAddress: stellarAccount,
          memo: memo || null,
        }
      });
    }

    // Return the interactive URL where the user completes the deposit
    // In production this points to your hosted deposit UI
    const interactiveUrl = `${process.env.FRONTEND_URL || 'https://app.dayfi.me'}/sep24/deposit?` +
      `transaction_id=${txId}&asset_code=${asset_code}&account=${stellarAccount}` +
      (amount ? `&amount=${amount}` : '') +
      (memo ? `&memo=${memo}` : '');

    res.json({
      type: 'interactive_customer_info_needed',
      url: interactiveUrl,
      id: txId,
    });
  } catch (err) {
    console.error('SEP-24 deposit error:', err);
    res.status(500).json({ error: err.message });
  }
});

// POST /sep24/transactions/withdraw/interactive
// Initiates a withdrawal — returns URL for hosted flow
router.post('/transactions/withdraw/interactive', sep10Auth, async (req, res) => {
  const { asset_code, account, amount, dest, dest_extra } = req.body;

  if (!asset_code || !SUPPORTED_ASSETS.includes(asset_code)) {
    return res.status(400).json({ error: `Unsupported asset: ${asset_code}` });
  }

  const stellarAccount = account || req.stellarAccount;
  if (!stellarAccount) {
    return res.status(400).json({ error: 'account required' });
  }

  try {
    const txId = uuidv4();

    const user = await prisma.user.findFirst({
      where: { stellarPublicKey: stellarAccount }
    });

    if (user) {
      await prisma.transaction.create({
        data: {
          id: txId,
          userId: user.id,
          type: 'send',
          status: 'pending',
          amount: parseFloat(amount) || 0,
          asset: asset_code,
          network: 'stellar',
          fromAddress: stellarAccount,
          toAddress: dest || 'pending',
          memo: dest_extra || null,
        }
      });
    }

    const interactiveUrl = `${process.env.FRONTEND_URL || 'https://app.dayfi.me'}/sep24/withdraw?` +
      `transaction_id=${txId}&asset_code=${asset_code}&account=${stellarAccount}` +
      (amount ? `&amount=${amount}` : '');

    res.json({
      type: 'interactive_customer_info_needed',
      url: interactiveUrl,
      id: txId,
    });
  } catch (err) {
    console.error('SEP-24 withdraw error:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /sep24/transaction?id=...
// Returns status of a single transaction
router.get('/transaction', sep10Auth, async (req, res) => {
  const { id, stellar_transaction_id } = req.query;

  if (!id && !stellar_transaction_id) {
    return res.status(400).json({ error: 'id or stellar_transaction_id required' });
  }

  try {
    const tx = await prisma.transaction.findFirst({
      where: id
        ? { id }
        : { stellarTxHash: stellar_transaction_id }
    });

    if (!tx) return res.status(404).json({ error: 'Transaction not found' });

    res.json({ transaction: formatSep24Tx(tx) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /sep24/transactions
// Returns transaction history for an account
router.get('/transactions', sep10Auth, async (req, res) => {
  const { asset_code, limit = 20, paging_id, no_older_than, kind } = req.query;

  try {
    let user = null;
    if (req.userId) {
      user = await prisma.user.findUnique({ where: { id: req.userId } });
    } else if (req.stellarAccount) {
      user = await prisma.user.findFirst({ where: { stellarPublicKey: req.stellarAccount } });
    }

    if (!user) return res.status(404).json({ error: 'Account not found' });

    const where = {
      userId: user.id,
      ...(asset_code && { asset: asset_code }),
      ...(kind && { type: kind === 'deposit' ? 'receive' : 'send' }),
      ...(no_older_than && { createdAt: { gte: new Date(no_older_than) } }),
    };

    const transactions = await prisma.transaction.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: parseInt(limit),
      ...(paging_id && { cursor: { id: paging_id }, skip: 1 }),
    });

    res.json({ transactions: transactions.map(formatSep24Tx) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /sep24/transaction — update status (internal use)
router.patch('/transaction/:id', authenticate, async (req, res) => {
  const { status, stellarTxHash, amount } = req.body;

  try {
    const tx = await prisma.transaction.update({
      where: { id: req.params.id },
      data: {
        ...(status && { status }),
        ...(stellarTxHash && { stellarTxHash }),
        ...(amount && { amount: parseFloat(amount) }),
      }
    });
    res.json({ transaction: formatSep24Tx(tx) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

function formatSep24Tx(tx) {
  return {
    id: tx.id,
    kind: tx.type === 'receive' ? 'deposit' : 'withdrawal',
    status: tx.status,
    amount_in: tx.type === 'receive' ? tx.amount?.toString() : undefined,
    amount_out: tx.type === 'send' ? tx.amount?.toString() : undefined,
    amount_fee: '0',
    asset_code: tx.asset,
    stellar_transaction_id: tx.stellarTxHash,
    from: tx.fromAddress,
    to: tx.toAddress,
    memo: tx.memo,
    started_at: tx.createdAt?.toISOString(),
    completed_at: tx.status === 'confirmed' ? tx.updatedAt?.toISOString() : null,
    stellar_memo: tx.memo,
    more_info_url: `https://${HOME_DOMAIN}/tx/${tx.id}`,
  };
}

export default router;
