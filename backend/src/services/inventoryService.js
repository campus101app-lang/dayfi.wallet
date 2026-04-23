// src/services/inventoryService.js
import { PrismaClient } from '@prisma/client';
import admin from 'firebase-admin';

const prisma = new PrismaClient();

// ─── Lazy Firebase init (reuses existing firebaseInit if present) ─────────────

function getFirebaseApp() {
  if (admin.apps.length > 0) return admin.apps[0];
  return admin.initializeApp({
    credential: admin.credential.cert({
      projectId:   process.env.FIREBASE_PROJECT_ID,
      privateKey:  process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    }),
  });
}

// ─── Get all inventory items for a user ───────────────────────────────────────

export async function getInventory(userId) {
  return prisma.inventoryItem.findMany({
    where:   { userId },
    orderBy: { createdAt: 'asc' },
  });
}

// ─── Create a new inventory item ──────────────────────────────────────────────

export async function createItem(userId, data) {
  // Ensure user is marked as merchant
  await prisma.user.update({
    where: { id: userId },
    data:  { isMerchant: true },
  });

  return prisma.inventoryItem.create({
    data: {
      userId,
      name:      data.name,
      sku:       data.sku       ?? null,
      priceUsdc: parseFloat(data.priceUsdc),
      stock:     parseInt(data.stock     ?? 0),
      threshold: parseInt(data.threshold ?? 5),
      barcode:   data.barcode   ?? null,
      imageUrl:  data.imageUrl  ?? null,
      category:  data.category  ?? null,
    },
  });
}

// ─── Update stock (delta or absolute) + trigger low-stock alert ───────────────

export async function updateStock(userId, itemId, { delta, absolute }) {
  // Fetch current item — verify ownership
  const item = await prisma.inventoryItem.findFirst({
    where: { id: itemId, userId },
  });
  if (!item) throw new Error('Item not found');

  const newStock = absolute !== undefined
    ? parseInt(absolute)
    : Math.max(0, item.stock + parseInt(delta));

  const updated = await prisma.inventoryItem.update({
    where: { id: itemId },
    data:  { stock: newStock },
  });

  // ── Low-stock check ─────────────────────────────────────────────────────────
  if (newStock <= updated.threshold) {
    await sendLowStockAlert(userId, updated).catch(err =>
      console.warn('⚠️  FCM alert failed:', err.message),
    );
  }

  return updated;
}

// ─── Full item update (name, price, threshold, etc.) ─────────────────────────

export async function updateItem(userId, itemId, data) {
  const item = await prisma.inventoryItem.findFirst({
    where: { id: itemId, userId },
  });
  if (!item) throw new Error('Item not found');

  return prisma.inventoryItem.update({
    where: { id: itemId },
    data: {
      ...(data.name      !== undefined && { name:      data.name }),
      ...(data.sku       !== undefined && { sku:       data.sku }),
      ...(data.priceUsdc !== undefined && { priceUsdc: parseFloat(data.priceUsdc) }),
      ...(data.stock     !== undefined && { stock:     parseInt(data.stock) }),
      ...(data.threshold !== undefined && { threshold: parseInt(data.threshold) }),
      ...(data.barcode   !== undefined && { barcode:   data.barcode }),
      ...(data.imageUrl  !== undefined && { imageUrl:  data.imageUrl }),
      ...(data.category  !== undefined && { category:  data.category }),
    },
  });
}

// ─── Delete item ──────────────────────────────────────────────────────────────

export async function deleteItem(userId, itemId) {
  const item = await prisma.inventoryItem.findFirst({
    where: { id: itemId, userId },
  });
  if (!item) throw new Error('Item not found');
  await prisma.inventoryItem.delete({ where: { id: itemId } });
  return { deleted: true };
}

// ─── Send low-stock FCM push notification ─────────────────────────────────────

async function sendLowStockAlert(userId, item) {
  const tokens = await prisma.deviceToken.findMany({ where: { userId } });
  if (!tokens.length) return;

  const app = getFirebaseApp();
  const message = {
    notification: {
      title: '🔴 Low Stock Alert',
      body:  `Only ${item.stock} unit${item.stock === 1 ? '' : 's'} left of ${item.name}`,
    },
    data: {
      type:   'low_stock',
      itemId: item.id,
      name:   item.name,
      stock:  String(item.stock),
    },
    tokens: tokens.map(t => t.token),
  };

  const response = await admin.messaging(app).sendEachForMulticast(message);
  console.log(`📲 Low-stock alert: ${response.successCount} sent, ${response.failureCount} failed`);
}

// ─── Generate compressed on-chain memo (max 28 chars for Stellar) ─────────────
// Format: "ID:xxx|Q:2|T:10.50" — truncated to 28 chars if needed

export function generateMemoReceipt(items, totalUsdc) {
  // items = [{ id, name, qty, priceUsdc }]
  const parts = items.map(i => {
    const shortId = i.id.slice(-4); // last 4 chars of cuid
    return `${shortId}:${i.qty}`;
  });

  // Build memo: "I:a1b2:2,c3d4:1|T:5.00"
  const itemsStr = parts.join(',');
  const raw = `I:${itemsStr}|T:${parseFloat(totalUsdc).toFixed(2)}`;

  return raw.length <= 28 ? raw : raw.substring(0, 28);
}

// ─── Build SEP-0007 Stellar URI for QR / NFC ─────────────────────────────────
// web+stellar:pay?destination=G...&amount=10&asset_code=USDC&asset_issuer=G...&memo=...

export function buildStellarPayUri({ destination, amountUsdc, memo }) {
  const USDC_ISSUER = process.env.USDC_ISSUER ||
    'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN';

  const params = new URLSearchParams({
    destination,
    amount:        parseFloat(amountUsdc).toFixed(7),
    asset_code:    'USDC',
    asset_issuer:  USDC_ISSUER,
  });

  if (memo) params.set('memo', memo.substring(0, 28));

  return `web+stellar:pay?${params.toString()}`;
}