// src/services/bitcoinWalletService.js
// Native Bitcoin wallet — P2WPKH (native SegWit, bc1... addresses)
// Uses bitcoinjs-lib + Blockstream Esplora API (no API key needed)

import * as bitcoin from 'bitcoinjs-lib';
import * as ecc from 'tiny-secp256k1';
import { BIP32Factory } from 'bip32';
import * as bip39 from 'bip39';
import crypto from 'crypto';
import { PrismaClient } from '@prisma/client';

bitcoin.initEccLib(ecc);
const bip32 = BIP32Factory(ecc);

const prisma = new PrismaClient();

const isTestnet = process.env.STELLAR_NETWORK !== 'mainnet';
const NETWORK = isTestnet ? bitcoin.networks.testnet : bitcoin.networks.bitcoin;

// Esplora API (Blockstream) — no key required
const ESPLORA_BASE = isTestnet
  ? 'https://blockstream.info/testnet/api'
  : 'https://blockstream.info/api';

// Mempool.space as fallback
const MEMPOOL_BASE = isTestnet
  ? 'https://mempool.space/testnet/api'
  : 'https://mempool.space/api';

// ─── Encryption ───────────────────────────────────────────────────────────────

const ALGORITHM = 'aes-256-gcm';
const ENCRYPTION_KEY = Buffer.from(
  process.env.WALLET_ENCRYPTION_KEY || 'a'.repeat(64), 'hex'
);

function encrypt(text) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
  let enc = cipher.update(text, 'utf8', 'hex');
  enc += cipher.final('hex');
  return `${iv.toString('hex')}:${cipher.getAuthTag().toString('hex')}:${enc}`;
}

function decrypt(encText) {
  const [ivHex, tagHex, enc] = encText.split(':');
  const decipher = crypto.createDecipheriv(ALGORITHM, ENCRYPTION_KEY, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  let dec = decipher.update(enc, 'hex', 'utf8');
  dec += decipher.final('utf8');
  return dec;
}

// ─── Wallet creation ─────────────────────────────────────────────────────────

export async function createBitcoinWallet() {
  // Generate a random mnemonic → HD wallet → derive first address
  const mnemonic = bip39.generateMnemonic(256); // 24 words
  const seed = await bip39.mnemonicToSeed(mnemonic);
  const root = bip32.fromSeed(seed, NETWORK);

  // BIP-84 derivation path: m/84'/0'/0'/0/0 (native SegWit)
  const coinType = isTestnet ? 1 : 0;
  const child = root.derivePath(`m/84'/${coinType}'/0'/0/0`);

  // P2WPKH address (bc1...)
  const { address } = bitcoin.payments.p2wpkh({
    pubkey: Buffer.from(child.publicKey),
    network: NETWORK,
  });

  // Store WIF private key (encrypted)
  const wif = child.toWIF();

  return {
    publicKey: address,
    encryptedSecretKey: encrypt(JSON.stringify({ wif, mnemonic })),
  };
}

// ─── Balance fetching ─────────────────────────────────────────────────────────

export async function getBitcoinBalance(btcAddress) {
  try {
    const res = await fetch(`${ESPLORA_BASE}/address/${btcAddress}`);
    if (!res.ok) return { BTC: 0, BTC_unconfirmed: 0 };

    const data = await res.json();
    const confirmedSats = (data.chain_stats?.funded_txo_sum || 0) - (data.chain_stats?.spent_txo_sum || 0);
    const unconfirmedSats = (data.mempool_stats?.funded_txo_sum || 0) - (data.mempool_stats?.spent_txo_sum || 0);

    return {
      BTC: confirmedSats / 1e8,
      BTC_unconfirmed: unconfirmedSats / 1e8,
    };
  } catch (err) {
    console.error('Bitcoin balance error:', err.message);
    return { BTC: 0, BTC_unconfirmed: 0 };
  }
}

// ─── Get UTXOs ────────────────────────────────────────────────────────────────

async function getUTXOs(address) {
  const res = await fetch(`${ESPLORA_BASE}/address/${address}/utxo`);
  if (!res.ok) throw new Error('Failed to fetch UTXOs');
  return res.json();
}

// ─── Get current fee rate (sat/vbyte) ─────────────────────────────────────────

async function getFeeRate() {
  try {
    const res = await fetch(`${MEMPOOL_BASE}/v1/fees/recommended`);
    const data = await res.json();
    return data.fastestFee || 20; // sat/vbyte
  } catch {
    return 20; // fallback
  }
}

// ─── Broadcast transaction ────────────────────────────────────────────────────

async function broadcastTx(txHex) {
  const res = await fetch(`${ESPLORA_BASE}/tx`, {
    method: 'POST',
    headers: { 'Content-Type': 'text/plain' },
    body: txHex,
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Broadcast failed: ${err}`);
  }
  return res.text(); // returns txid
}

// ─── Send BTC ────────────────────────────────────────────────────────────────

export async function sendBitcoin({ fromUserId, toAddress, amountBTC, memo }) {
  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.btcPublicKey || !sender?.btcSecretKey) {
    throw new Error('Bitcoin wallet not found');
  }

  const { wif } = JSON.parse(decrypt(sender.btcSecretKey));
  const keyPair = bitcoin.ECPair.fromWIF(wif, NETWORK);

  const fromAddress = sender.btcPublicKey;
  const amountSats = Math.round(amountBTC * 1e8);

  // Fetch UTXOs
  const utxos = await getUTXOs(fromAddress);
  if (!utxos.length) throw new Error('No UTXOs available — wallet may be empty');

  const feeRate = await getFeeRate();

  // Build PSBT
  const psbt = new bitcoin.Psbt({ network: NETWORK });

  // Add inputs
  let totalInput = 0;
  for (const utxo of utxos) {
    // Fetch raw tx for input
    const txRes = await fetch(`${ESPLORA_BASE}/tx/${utxo.txid}/hex`);
    const txHex = await txRes.text();

    psbt.addInput({
      hash: utxo.txid,
      index: utxo.vout,
      witnessUtxo: {
        script: bitcoin.payments.p2wpkh({
          pubkey: Buffer.from(keyPair.publicKey),
          network: NETWORK,
        }).output,
        value: utxo.value,
      },
    });
    totalInput += utxo.value;
    if (totalInput >= amountSats + feeRate * 200) break; // enough inputs
  }

  // Estimate fee (P2WPKH: ~110 vbytes for 1-in 2-out)
  const estimatedVbytes = 110 + (psbt.inputCount - 1) * 41;
  const feeSats = feeRate * estimatedVbytes;

  if (totalInput < amountSats + feeSats) {
    throw new Error(`Insufficient balance. Need ${(amountSats + feeSats) / 1e8} BTC`);
  }

  // Add recipient output
  psbt.addOutput({ address: toAddress, value: amountSats });

  // Change output
  const change = totalInput - amountSats - feeSats;
  if (change > 546) { // dust threshold
    psbt.addOutput({ address: fromAddress, value: change });
  }

  // Add OP_RETURN memo if provided
  if (memo) {
    const memoData = Buffer.from(memo.substring(0, 40), 'utf8');
    const embed = bitcoin.payments.embed({ data: [memoData] });
    psbt.addOutput({ script: embed.output, value: 0 });
  }

  // Sign all inputs
  psbt.signAllInputs(keyPair);
  psbt.finalizeAllInputs();

  const txHex = psbt.extractTransaction().toHex();
  const txid = await broadcastTx(txHex);

  // Record transaction
  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: 'send',
      status: 'pending', // BTC needs confirmations
      amount: amountBTC,
      asset: 'BTC',
      network: 'bitcoin',
      fromAddress,
      toAddress,
      btcTxHash: txid,
      fee: feeSats / 1e8,
      memo: memo || null,
    }
  });

  return {
    hash: txid,
    network: 'bitcoin',
    asset: 'BTC',
    amount: amountBTC,
    feeBTC: feeSats / 1e8,
    destination: toAddress,
    explorer: `${isTestnet ? 'https://blockstream.info/testnet' : 'https://blockstream.info'}/tx/${txid}`,
  };
}

// ─── Transaction history ──────────────────────────────────────────────────────

export async function getBitcoinTransactions(btcAddress, limit = 10) {
  try {
    const res = await fetch(`${ESPLORA_BASE}/address/${btcAddress}/txs`);
    if (!res.ok) return [];
    const txs = await res.json();
    return txs.slice(0, limit).map(tx => ({
      hash: tx.txid,
      confirmed: tx.status?.confirmed || false,
      blockHeight: tx.status?.block_height,
      timestamp: tx.status?.block_time,
    }));
  } catch {
    return [];
  }
}

export { decrypt as btcDecrypt };
