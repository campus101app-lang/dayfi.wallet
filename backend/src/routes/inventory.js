// src/routes/inventoryRoutes.js
import express from 'express';
import { body, param, validationResult } from 'express-validator';
import { authenticate } from '../middleware/auth.js';
import {
  getInventory,
  createItem,
  updateStock,
  updateItem,
  deleteItem,
  buildStellarPayUri,
  generateMemoReceipt,
} from '../services/inventoryService.js';

const router = express.Router();

// ─── GET /api/inventory ───────────────────────────────────────────────────────
router.get('/', authenticate, async (req, res) => {
  try {
    const items = await getInventory(req.user.id);
    res.json({ items });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /api/inventory ──────────────────────────────────────────────────────
router.post('/', authenticate, [
  body('name').notEmpty().trim(),
  body('priceUsdc').isFloat({ min: 0 }),
  body('stock').optional().isInt({ min: 0 }),
  body('threshold').optional().isInt({ min: 0 }),
  body('sku').optional().trim(),
  body('category').optional().trim(),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  try {
    const item = await createItem(req.user.id, req.body);
    res.status(201).json({ item });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── PATCH /api/inventory/:id/stock ──────────────────────────────────────────
router.patch('/:id/stock', authenticate, async (req, res) => {
  const { delta, absolute } = req.body;
  if (delta === undefined && absolute === undefined) {
    return res.status(400).json({ error: 'Provide delta or absolute' });
  }
  try {
    const item = await updateStock(req.user.id, req.params.id, { delta, absolute });
    res.json({ item });
  } catch (err) {
    res.status(err.message === 'Item not found' ? 404 : 500).json({ error: err.message });
  }
});

// ─── PATCH /api/inventory/:id ─────────────────────────────────────────────────
router.patch('/:id', authenticate, [
  body('priceUsdc').optional().isFloat({ min: 0 }),
  body('stock').optional().isInt({ min: 0 }),
  body('threshold').optional().isInt({ min: 0 }),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  try {
    const item = await updateItem(req.user.id, req.params.id, req.body);
    res.json({ item });
  } catch (err) {
    res.status(err.message === 'Item not found' ? 404 : 500).json({ error: err.message });
  }
});

// ─── DELETE /api/inventory/:id ────────────────────────────────────────────────
router.delete('/:id', authenticate, async (req, res) => {
  try {
    await deleteItem(req.user.id, req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(err.message === 'Item not found' ? 404 : 500).json({ error: err.message });
  }
});

// ─── POST /api/inventory/checkout/uri ─────────────────────────────────────────
// Returns SEP-0007 URI for QR code + NFC payload
router.post('/checkout/uri', authenticate, [
  body('items').isArray({ min: 1 }),
  body('totalUsdc').isFloat({ min: 0.000001 }),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  try {
    const { items, totalUsdc } = req.body;
    const destination = req.user.stellarPublicKey;
    if (!destination) return res.status(400).json({ error: 'Merchant wallet not set up' });

    const memo = generateMemoReceipt(items, totalUsdc);
    const uri  = buildStellarPayUri({ destination, amountUsdc: totalUsdc, memo });

    res.json({ uri, memo, destination, totalUsdc });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

export default router;