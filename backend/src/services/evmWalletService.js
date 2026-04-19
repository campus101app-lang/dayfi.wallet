// src/services/evmWalletService.js
// Covers: Ethereum, Arbitrum, Polygon, Avalanche — one address, one key
// Assets: USDC on all 4 chains, XAU₮ (Tether Gold) on Ethereum

import { ethers } from 'ethers';
import crypto from 'crypto';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// ─── Encryption (same as walletService.js) ───────────────────────────────────

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

// ─── Network RPC config ───────────────────────────────────────────────────────

const NETWORKS = {
  ethereum: {
    name: 'Ethereum',
    rpc: process.env.ETH_RPC_URL || 'https://eth-mainnet.g.alchemy.com/v2/' + (process.env.ALCHEMY_API_KEY || ''),
    chainId: 1,
    explorer: 'https://etherscan.io',
    nativeSymbol: 'ETH',
  },
  arbitrum: {
    name: 'Arbitrum One',
    rpc: process.env.ARB_RPC_URL || 'https://arb-mainnet.g.alchemy.com/v2/' + (process.env.ALCHEMY_API_KEY || ''),
    chainId: 42161,
    explorer: 'https://arbiscan.io',
    nativeSymbol: 'ETH',
  },
  polygon: {
    name: 'Polygon',
    rpc: process.env.POLY_RPC_URL || 'https://polygon-mainnet.g.alchemy.com/v2/' + (process.env.ALCHEMY_API_KEY || ''),
    chainId: 137,
    explorer: 'https://polygonscan.com',
    nativeSymbol: 'MATIC',
  },
  avalanche: {
    name: 'Avalanche C-Chain',
    rpc: process.env.AVAX_RPC_URL || 'https://api.avax.network/ext/bc/C/rpc',
    chainId: 43114,
    explorer: 'https://snowtrace.io',
    nativeSymbol: 'AVAX',
  },
};

// ─── ERC-20 token addresses per network ──────────────────────────────────────

const TOKEN_ADDRESSES = {
  // USDC (Circle)
  USDC: {
    ethereum:  process.env.USDC_ETH_ADDRESS  || '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    arbitrum:  process.env.USDC_ARB_ADDRESS  || '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    polygon:   process.env.USDC_POLY_ADDRESS || '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
    avalanche: process.env.USDC_AVAX_ADDRESS || '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
  },
  // XAU₮ — Tether Gold (Ethereum only)
  XAUT: {
    ethereum: process.env.XAUT_ETH_ADDRESS || '0x68749665FF8D2d112Fa859AA293F07A622782F38',
  },
};

// Minimal ERC-20 ABI for balance + transfer
const ERC20_ABI = [
  'function balanceOf(address owner) view returns (uint256)',
  'function transfer(address to, uint256 amount) returns (bool)',
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
];

// ─── Provider factory ─────────────────────────────────────────────────────────

function getProvider(network = 'ethereum') {
  const config = NETWORKS[network];
  if (!config) throw new Error(`Unknown EVM network: ${network}`);

  return new ethers.JsonRpcProvider(config.rpc, {
    chainId: config.chainId,
    name: network,
    staticNetwork: true 
  });
}

function getWallet(privateKey, network = 'ethereum') {
  const provider = getProvider(network);
  return new ethers.Wallet(privateKey, provider);
}

// ─── Wallet creation ─────────────────────────────────────────────────────────

export async function createEVMWallet() {
  const wallet = ethers.Wallet.createRandom();
  return {
    publicKey: wallet.address,
    encryptedSecretKey: encrypt(wallet.privateKey),
  };
}

// ─── Balance fetching ─────────────────────────────────────────────────────────

export async function getEVMBalances(evmAddress) {
  const balances = {};

  // Fetch USDC on all 4 networks in parallel
  const usdcResults = await Promise.allSettled(
    Object.entries(TOKEN_ADDRESSES.USDC).map(async ([network, tokenAddress]) => {
      try {
        const config = NETWORKS[network];
        
        // 1. Validation: Skip if the RPC is missing or incomplete (common with Alchemy keys)
        if (!config.rpc || config.rpc.endsWith('/') || config.rpc.includes('undefined')) {
          return { network, balance: 0 };
        }

        const provider = getProvider(network);
        const contract = new ethers.Contract(tokenAddress, ERC20_ABI, provider);

        // 2. Add a simple timeout so we don't wait forever on a dead node
        const timeout = new Promise((_, reject) => 
          setTimeout(() => reject(new Error('RPC Timeout')), 4000)
        );

        const fetchPromise = Promise.all([
          contract.balanceOf(evmAddress),
          contract.decimals(),
        ]);

        const [raw, decimals] = await Promise.race([fetchPromise, timeout]);
        return { network, balance: parseFloat(ethers.formatUnits(raw, decimals)) };
      } catch (err) {
        // Silently catch the error so it doesn't spam the console
        return { network, balance: 0 };
      }
    })
  );

  for (const result of usdcResults) {
    if (result.status === 'fulfilled') {
      const { network, balance } = result.value;
      balances[`USDC_${network}`] = balance;
    }
  }

  // 3. Fetch XAU₮ on Ethereum (Applying the same defensive logic)
  try {
    const ethConfig = NETWORKS.ethereum;
    if (ethConfig.rpc && !ethConfig.rpc.endsWith('/') && !ethConfig.rpc.includes('undefined')) {
      const provider = getProvider('ethereum');
      const contract = new ethers.Contract(TOKEN_ADDRESSES.XAUT.ethereum, ERC20_ABI, provider);
      const [raw, decimals] = await Promise.all([
        contract.balanceOf(evmAddress),
        contract.decimals(),
      ]);
      balances['XAUT_ethereum'] = parseFloat(ethers.formatUnits(raw, decimals));
    } else {
      balances['XAUT_ethereum'] = 0;
    }
  } catch (_) {
    balances['XAUT_ethereum'] = 0;
  }

  return balances;
}

// ─── Send ERC-20 token ────────────────────────────────────────────────────────

export async function sendEVMToken({
  fromUserId,
  toAddress,
  amount,
  asset,       // 'USDC' | 'XAUT'
  network,     // 'ethereum' | 'arbitrum' | 'polygon' | 'avalanche'
  memo,
}) {
  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.evmPublicKey || !sender?.evmSecretKey) {
    throw new Error('EVM wallet not found');
  }

  const privateKey = decrypt(sender.evmSecretKey);
  const wallet = getWallet(privateKey, network);

  const tokenAddresses = TOKEN_ADDRESSES[asset];
  if (!tokenAddresses) throw new Error(`Unsupported EVM asset: ${asset}`);

  const tokenAddress = tokenAddresses[network];
  if (!tokenAddress) throw new Error(`${asset} not available on ${network}`);

  const contract = new ethers.Contract(tokenAddress, ERC20_ABI, wallet);
  const decimals = await contract.decimals();
  const amountWei = ethers.parseUnits(amount.toString(), decimals);

  // Estimate gas
  const gasEstimate = await contract.transfer.estimateGas(toAddress, amountWei);
  const feeData = await wallet.provider.getFeeData();

  const tx = await contract.transfer(toAddress, amountWei, {
    gasLimit: (gasEstimate * 120n) / 100n, // +20% buffer
    maxFeePerGas: feeData.maxFeePerGas,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
  });

  const receipt = await tx.wait();

  // Record transaction
  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: 'send',
      status: 'confirmed',
      amount: parseFloat(amount),
      asset,
      network,
      fromAddress: sender.evmPublicKey,
      toAddress,
      evmTxHash: receipt.hash,
      memo: memo || null,
    }
  });

  return {
    hash: receipt.hash,
    network,
    asset,
    amount,
    destination: toAddress,
    explorer: `${NETWORKS[network].explorer}/tx/${receipt.hash}`,
  };
}

// ─── Get EVM receive addresses ────────────────────────────────────────────────

export function getEVMNetworks(evmAddress) {
  return [
    {
      network: 'ethereum',
      name: 'Ethereum',
      address: evmAddress,
      assets: ['USDC', 'XAUT'],
      icon: 'ethereum',
    },
    {
      network: 'arbitrum',
      name: 'Arbitrum One',
      address: evmAddress,
      assets: ['USDC'],
      icon: 'arbitrum',
    },
    {
      network: 'polygon',
      name: 'Polygon',
      address: evmAddress,
      assets: ['USDC'],
      icon: 'polygon',
    },
    {
      network: 'avalanche',
      name: 'Avalanche',
      address: evmAddress,
      assets: ['USDC'],
      icon: 'avalanche',
    },
  ];
}

export { NETWORKS, TOKEN_ADDRESSES, decrypt as evmDecrypt };
