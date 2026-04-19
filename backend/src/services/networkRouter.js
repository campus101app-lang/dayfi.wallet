// src/services/networkRouter.js
// Routes send/receive operations to the correct blockchain service
// based on asset + network selection

import { sendAsset as sendStellarAsset, getWalletBalances as getStellarBalances } from './walletService.js';
import { sendEVMToken, getEVMBalances, getEVMNetworks, createEVMWallet } from './evmWalletService.js';
import { sendBitcoin, getBitcoinBalance, createBitcoinWallet } from './bitcoinWalletService.js';
import { sendSolanaUSDC, sendSOL, getSolanaBalances, createSolanaWallet } from './solanaWalletService.js';
import { createStellarWallet } from './walletService.js';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// ─── Asset → supported networks map ──────────────────────────────────────────

export const ASSET_NETWORKS = {
  USDC: ['stellar', 'ethereum', 'arbitrum', 'polygon', 'avalanche', 'solana'],
  XLM:  ['stellar'],
  BTC:  ['stellar', 'bitcoin'],
  GOLD: ['stellar', 'ethereum'], // XAU₮ on ETH, GOLD on Stellar
  XAUT: ['ethereum'],            // Tether Gold native ERC-20
  SOL:  ['solana'],
  ETH:  ['ethereum'],
};

// Recommended network per asset (best for B2C payments)
export const RECOMMENDED_NETWORK = {
  USDC: 'stellar',   // cheapest, fastest
  XLM:  'stellar',
  BTC:  'bitcoin',
  GOLD: 'stellar',
  XAUT: 'ethereum',
  SOL:  'solana',
};

// ─── Create all wallets on signup ─────────────────────────────────────────────

export async function createAllWallets(userId) {
  console.log(`🔑 Creating wallets for user ${userId}...`);

  const results = await Promise.allSettled([
    createStellarWallet(),
    createEVMWallet(),
    createBitcoinWallet(),
    createSolanaWallet(),
  ]);

  const [stellar, evm, btc, solana] = results;

  const updateData = {};

  if (stellar.status === 'fulfilled') {
    updateData.stellarPublicKey = stellar.value.publicKey;
    updateData.stellarSecretKey = stellar.value.encryptedSecretKey;
    console.log(`  ✅ Stellar: ${stellar.value.publicKey}`);
  } else {
    console.error('  ❌ Stellar wallet failed:', stellar.reason?.message);
  }

  if (evm.status === 'fulfilled') {
    updateData.evmPublicKey = evm.value.publicKey;
    updateData.evmSecretKey = evm.value.encryptedSecretKey;
    console.log(`  ✅ EVM: ${evm.value.publicKey}`);
  } else {
    console.error('  ❌ EVM wallet failed:', evm.reason?.message);
  }

  if (btc.status === 'fulfilled') {
    updateData.btcPublicKey = btc.value.publicKey;
    updateData.btcSecretKey = btc.value.encryptedSecretKey;
    console.log(`  ✅ Bitcoin: ${btc.value.publicKey}`);
  } else {
    console.error('  ❌ Bitcoin wallet failed:', btc.reason?.message);
  }

  if (solana.status === 'fulfilled') {
    updateData.solanaPublicKey = solana.value.publicKey;
    updateData.solanaSecretKey = solana.value.encryptedSecretKey;
    console.log(`  ✅ Solana: ${solana.value.publicKey}`);
  } else {
    console.error('  ❌ Solana wallet failed:', solana.reason?.message);
  }

  // Update user with all wallet addresses
  await prisma.user.update({
    where: { id: userId },
    data: updateData,
  });

  return updateData;
}

// ─── Get all balances across all chains ───────────────────────────────────────

export async function getAllBalances(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new Error('User not found');

  const results = await Promise.allSettled([
    user.stellarPublicKey ? getStellarBalances(user.stellarPublicKey) : Promise.resolve({}),
    user.evmPublicKey     ? getEVMBalances(user.evmPublicKey)         : Promise.resolve({}),
    user.btcPublicKey     ? getBitcoinBalance(user.btcPublicKey)      : Promise.resolve({}),
    user.solanaPublicKey  ? getSolanaBalances(user.solanaPublicKey)   : Promise.resolve({}),
  ]);

  const [stellarR, evmR, btcR, solanaR] = results;

  const stellar = stellarR.status === 'fulfilled' ? stellarR.value : {};
  const evm     = evmR.status     === 'fulfilled' ? evmR.value     : {};
  const btc     = btcR.status     === 'fulfilled' ? btcR.value     : {};
  const solana  = solanaR.status  === 'fulfilled' ? solanaR.value  : {};

  // Approximate USD prices
  const prices = {
    USDC: 1, XLM: 0.11, BTC: 95000, GOLD: 3200,
    XAUT: 3200, SOL: 170, ETH: 3500,
  };

  // Aggregate by asset (sum across all networks)
  const aggregated = {
    USDC:  (stellar.USDC || 0) + (evm.USDC_ethereum || 0) + (evm.USDC_arbitrum || 0) + (evm.USDC_polygon || 0) + (evm.USDC_avalanche || 0) + (solana.USDC_solana || 0),
    XLM:   stellar.XLM  || 0,
    BTC:   (stellar.BTC || 0) + (btc.BTC || 0),
    GOLD:  stellar.GOLD || 0,
    XAUT:  evm.XAUT_ethereum || 0,
    SOL:   solana.SOL || 0,
  };

  const totalUSD = Object.entries(aggregated).reduce((sum, [asset, amount]) => {
    return sum + (amount * (prices[asset] || 0));
  }, 0);

  return {
    // Per-chain breakdown
    byChain: {
      stellar,
      evm,
      bitcoin: btc,
      solana,
    },
    // Aggregated by asset
    balances: aggregated,
    totalUSD,
    // Addresses
    addresses: {
      stellar: user.stellarPublicKey,
      evm:     user.evmPublicKey,
      bitcoin: user.btcPublicKey,
      solana:  user.solanaPublicKey,
    },
  };
}

// ─── Get all receive addresses ────────────────────────────────────────────────

export async function getAllAddresses(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new Error('User not found');

  return {
    dayfiUsername: `${user.username}@dayfi.me`,
    networks: [
      // Stellar — USDC, XLM, BTC, GOLD
      {
        chain: 'stellar',
        name: 'Stellar',
        address: user.stellarPublicKey,
        assets: ['USDC', 'XLM', 'BTC', 'GOLD'],
        recommended: true,
        description: 'Fastest & cheapest. Best for everyday transfers.',
      },
      // EVM — same address for all 4 EVM chains
      ...(user.evmPublicKey ? getEVMNetworks(user.evmPublicKey) : []),
      // Bitcoin
      ...(user.btcPublicKey ? [{
        chain: 'bitcoin',
        name: 'Bitcoin',
        address: user.btcPublicKey,
        assets: ['BTC'],
        description: 'Native Bitcoin network.',
      }] : []),
      // Solana
      ...(user.solanaPublicKey ? [{
        chain: 'solana',
        name: 'Solana',
        address: user.solanaPublicKey,
        assets: ['USDC', 'SOL'],
        description: 'Fast & low-cost USDC on Solana.',
      }] : []),
    ],
  };
}

// ─── Route a send operation ───────────────────────────────────────────────────

export async function routeSend({
  fromUserId,
  to,
  amount,
  asset,
  network,
  memo,
}) {
  // Validate asset+network combo
  const supportedNetworks = ASSET_NETWORKS[asset];
  if (!supportedNetworks) throw new Error(`Unsupported asset: ${asset}`);
  if (!supportedNetworks.includes(network)) {
    throw new Error(`${asset} is not available on ${network}. Supported: ${supportedNetworks.join(', ')}`);
  }

  // Route to correct service
  switch (network) {
    case 'stellar':
      return await sendStellarAsset(fromUserId, to, amount, asset, memo);

    case 'ethereum':
    case 'arbitrum':
    case 'polygon':
    case 'avalanche':
      return await sendEVMToken({ fromUserId, toAddress: to, amount, asset: asset === 'GOLD' ? 'XAUT' : asset, network, memo });

    case 'bitcoin':
      return await sendBitcoin({ fromUserId, toAddress: to, amountBTC: amount, memo });

    case 'solana':
      if (asset === 'SOL') {
        return await sendSOL({ fromUserId, toAddress: to, amountSOL: amount, memo });
      }
      return await sendSolanaUSDC({ fromUserId, toAddress: to, amount, memo });

    default:
      throw new Error(`Unknown network: ${network}`);
  }
}

export { ASSET_NETWORKS as assetNetworks };
