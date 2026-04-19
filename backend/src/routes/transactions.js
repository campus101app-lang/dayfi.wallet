// src/routes/transactions.js
import express from 'express';
import { PrismaClient } from '@prisma/client';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();
const prisma = new PrismaClient();

// GET /api/transactions
router.get('/', authenticate, async (req, res) => {
  const { page = 1, limit = 20, type, asset } = req.query;
  const skip = (parseInt(page) - 1) * parseInt(limit);

  const where = {
    userId: req.user.id,
    ...(type && { type }),
    ...(asset && { asset }),
  };

  try {
    const [transactions, total] = await Promise.all([
      prisma.transaction.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: parseInt(limit),
        skip,
      }),
      prisma.transaction.count({ where }),
    ]);

    res.json({
      transactions,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit)),
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/transactions/:id
router.get('/:id', authenticate, async (req, res) => {
  try {
    const tx = await prisma.transaction.findFirst({
      where: { id: req.params.id, userId: req.user.id }
    });
    
    if (!tx) return res.status(404).json({ error: 'Transaction not found' });
    res.json(tx);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

export default router;
