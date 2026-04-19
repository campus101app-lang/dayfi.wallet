// src/services/solanaWalletService.js
// Solana wallet — USDC on Solana (SPL Token)
// Uses @solana/web3.js + Helius RPC

import {
  Connection,
  Keypair,
  PublicKey,
  Transaction,
  sendAndConfirmTransaction,
  SystemProgram,
  LAMPORTS_PER_SOL,
} from '@solana/web3.js';
import {
  getOrCreateAssociatedTokenAccount,
  createTransferInstruction,
  getAccount,
  TOKEN_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getMint,
} from '@solana/spl-token';
import crypto from 'crypto';
import { PrismaClient } from '@prisma/client';
import bs58 from 'bs58';

const prisma = new PrismaClient();

const isTestnet = process.env.STELLAR_NETWORK !== 'mainnet';

// RPC endpoint — Helius recommended for reliability
const RPC_URL = isTestnet
  ? (process.env.SOLANA_RPC_URL || 'https://api.devnet.solana.com')
  : (process.env.SOLANA_RPC_URL || `https://mainnet.helius-rpc.com/?api-key=${process.env.HELIUS_API_KEY || ''}`);

const connection = new Connection(RPC_URL, 'confirmed');

// USDC mint address on Solana
const USDC_MINT = new PublicKey(
  isTestnet
    ? process.env.SOLANA_USDC_MINT || 'Gh9ZwEmdLJ8DscKNTkTqPbNwLNNBjuSzaG9Vp2KGtKJr' // devnet
    : process.env.SOLANA_USDC_MINT || 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v' // mainnet
);

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

export async function createSolanaWallet() {
  const keypair = Keypair.generate();
  const publicKey = keypair.publicKey.toBase58();
  const secretKeyBase58 = bs58.encode(keypair.secretKey);

  return {
    publicKey,
    encryptedSecretKey: encrypt(secretKeyBase58),
  };
}

// ─── Balance fetching ─────────────────────────────────────────────────────────

export async function getSolanaBalances(solanaAddress) {
  const pubkey = new PublicKey(solanaAddress);
  const balances = { SOL: 0, USDC_solana: 0 };

  try {
    // SOL balance
    const lamports = await connection.getBalance(pubkey);
    balances.SOL = lamports / LAMPORTS_PER_SOL;
  } catch (_) {}

  try {
    // USDC SPL token balance
    const tokenAccounts = await connection.getParsedTokenAccountsByOwner(pubkey, {
      mint: USDC_MINT,
    });

    if (tokenAccounts.value.length > 0) {
      const usdcInfo = tokenAccounts.value[0].account.data.parsed.info;
      balances.USDC_solana = parseFloat(usdcInfo.tokenAmount.uiAmountString || '0');
    }
  } catch (_) {}

  return balances;
}

// ─── Send USDC on Solana ──────────────────────────────────────────────────────

export async function sendSolanaUSDC({ fromUserId, toAddress, amount, memo }) {
  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.solanaPublicKey || !sender?.solanaSecretKey) {
    throw new Error('Solana wallet not found');
  }

  const secretKeyBase58 = decrypt(sender.solanaSecretKey);
  const secretKey = bs58.decode(secretKeyBase58);
  const fromKeypair = Keypair.fromSecretKey(secretKey);
  const fromPubkey = fromKeypair.publicKey;
  const toPubkey = new PublicKey(toAddress);

  // Get USDC mint decimals
  const mintInfo = await getMint(connection, USDC_MINT);
  const amountLamports = BigInt(Math.round(amount * Math.pow(10, mintInfo.decimals)));

  // Get or create sender's token account
  const fromTokenAccount = await getOrCreateAssociatedTokenAccount(
    connection,
    fromKeypair,
    USDC_MINT,
    fromPubkey
  );

  // Get or create recipient's token account
  const toTokenAccount = await getOrCreateAssociatedTokenAccount(
    connection,
    fromKeypair, // payer for account creation
    USDC_MINT,
    toPubkey
  );

  // Build transfer instruction
  const transferInstruction = createTransferInstruction(
    fromTokenAccount.address,
    toTokenAccount.address,
    fromPubkey,
    amountLamports,
    [],
    TOKEN_PROGRAM_ID
  );

  const transaction = new Transaction().add(transferInstruction);

  // Add memo if provided
  if (memo) {
    const { createMemoInstruction } = await import('@solana/spl-memo');
    transaction.add(createMemoInstruction(memo.substring(0, 100)));
  }

  // Get recent blockhash
  const { blockhash } = await connection.getLatestBlockhash();
  transaction.recentBlockhash = blockhash;
  transaction.feePayer = fromPubkey;

  // Send and confirm
  const signature = await sendAndConfirmTransaction(
    connection,
    transaction,
    [fromKeypair],
    { commitment: 'confirmed' }
  );

  // Record transaction
  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: 'send',
      status: 'confirmed',
      amount: parseFloat(amount),
      asset: 'USDC',
      network: 'solana',
      fromAddress: sender.solanaPublicKey,
      toAddress,
      solanaTxHash: signature,
      memo: memo || null,
    }
  });

  return {
    hash: signature,
    network: 'solana',
    asset: 'USDC',
    amount,
    destination: toAddress,
    explorer: `https://solscan.io/tx/${signature}${isTestnet ? '?cluster=devnet' : ''}`,
  };
}

// ─── Send native SOL ──────────────────────────────────────────────────────────

export async function sendSOL({ fromUserId, toAddress, amountSOL, memo }) {
  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.solanaPublicKey || !sender?.solanaSecretKey) {
    throw new Error('Solana wallet not found');
  }

  const secretKey = bs58.decode(decrypt(sender.solanaSecretKey));
  const fromKeypair = Keypair.fromSecretKey(secretKey);
  const toPubkey = new PublicKey(toAddress);
  const lamports = Math.round(amountSOL * LAMPORTS_PER_SOL);

  const transaction = new Transaction().add(
    SystemProgram.transfer({
      fromPubkey: fromKeypair.publicKey,
      toPubkey,
      lamports,
    })
  );

  const { blockhash } = await connection.getLatestBlockhash();
  transaction.recentBlockhash = blockhash;
  transaction.feePayer = fromKeypair.publicKey;

  const signature = await sendAndConfirmTransaction(connection, transaction, [fromKeypair]);

  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: 'send',
      status: 'confirmed',
      amount: amountSOL,
      asset: 'SOL',
      network: 'solana',
      fromAddress: sender.solanaPublicKey,
      toAddress,
      solanaTxHash: signature,
      memo: memo || null,
    }
  });

  return { hash: signature, network: 'solana', asset: 'SOL', amount: amountSOL };
}

export { connection, USDC_MINT, decrypt as solDecrypt };
