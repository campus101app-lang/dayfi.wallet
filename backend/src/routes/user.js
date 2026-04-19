// src/routes/user.js
import express from 'express';
import { PrismaClient } from '@prisma/client';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();
const prisma = new PrismaClient();

// GET /api/user/me
router.get('/me', authenticate, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: {
        id: true,
        email: true,
        username: true,
        stellarPublicKey: true,
        faceIdEnabled: true,
        isBackedUp: true,  // ← add this
        createdAt: true,
      },
    });
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ ...user, dayfiUsername: `${user.username}@dayfi.me` });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/user/device-token
// Register push notification token
router.post('/device-token', authenticate, async (req, res) => {
  const { token, platform } = req.body;
  
  if (!token || !platform) {
    return res.status(400).json({ error: 'token and platform required' });
  }

  try {
    await prisma.deviceToken.upsert({
      where: { token },
      update: { userId: req.user.id },
      create: {
        userId: req.user.id,
        token,
        platform,
      }
    });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

export default router;

// src/routes/transactions.js — export separately below
