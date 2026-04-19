#!/usr/bin/env node

/**
 * Setup script for Master Wallet auto-funding
 * 
 * Usage:
 *   node scripts/setup-master-wallet.js create    # Create new master wallet
 *   node scripts/setup-master-wallet.js encrypt <secret-key>  # Encrypt existing secret key
 */

import crypto from 'crypto';
import StellarSdk from '@stellar/stellar-sdk';
import readline from 'readline';

const ALGORITHM = 'aes-256-gcm';
const ENCRYPTION_KEY = Buffer.from(
  process.env.WALLET_ENCRYPTION_KEY || 'a'.repeat(64),
  'hex'
);

function encrypt(text) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
  let enc = cipher.update(text, 'utf8', 'hex');
  enc += cipher.final('hex');
  return `${iv.toString('hex')}:${cipher.getAuthTag().toString('hex')}:${enc}`;
}

function prompt(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

async function createNewWallet() {
  console.log('\n🔐 Creating new Master Wallet...\n');

  // Generate keypair
  const keypair = StellarSdk.Keypair.random();
  const publicKey = keypair.publicKey();
  const secretKey = keypair.secret();

  console.log('✅ Master Wallet Generated:\n');
  console.log(`📍 Public Key (MASTER_WALLET_PUBLIC_KEY):`);
  console.log(`   ${publicKey}\n`);

  console.log('🔑 Secret Key (encrypted for storage):\n');
  const encryptedSecret = encrypt(secretKey);
  console.log(`MASTER_WALLET_SECRET_KEY=${encryptedSecret}\n`);

  console.log('📋 Add these to your .env file in the backend folder:\n');
  console.log(`MASTER_WALLET_PUBLIC_KEY=${publicKey}`);
  console.log(`MASTER_WALLET_SECRET_KEY=${encryptedSecret}`);
  console.log(`FUNDING_AMOUNT=5\n`);

  console.log('⚠️  IMPORTANT SECURITY NOTES:');
  console.log('1. The public key is safe to commit to version control');
  console.log('2. The secret key is encrypted, but treat it as sensitive');
  console.log('3. Fund this wallet with XLM on Mainnet before using in production');
  console.log('4. Consider using a secret management system (AWS Secrets, HashiCorp Vault, etc.)\n');

  console.log('🚀 Next steps:');
  console.log('1. Fund the master wallet with XLM on Stellar Network');
  console.log('   - Mainnet: Transfer XLM to the public key above');
  console.log('   - Testnet: Use Friendbot: https://laboratory.stellar.org/#account-creator');
  console.log('2. Add the configuration to backend/.env');
  console.log('3. Restart the backend server\n');
}

async function encryptSecret() {
  const secretKey = await prompt('Enter the Stellar secret key (starts with S): ');

  if (!secretKey.startsWith('S')) {
    console.error('❌ Invalid secret key format. Must start with S\n');
    process.exit(1);
  }

  try {
    // Validate it's a valid Stellar secret
    StellarSdk.Keypair.fromSecret(secretKey);
    const encryptedSecret = encrypt(secretKey);

    console.log('\n✅ Secret key encrypted successfully:\n');
    console.log(`MASTER_WALLET_SECRET_KEY=${encryptedSecret}\n`);
    console.log('Add this to your backend/.env file\n');
  } catch (err) {
    console.error(`❌ Invalid secret key: ${err.message}\n`);
    process.exit(1);
  }
}

async function main() {
  const command = process.argv[2];

  if (command === 'create') {
    await createNewWallet();
  } else if (command === 'encrypt') {
    await encryptSecret();
  } else {
    console.log('\n📚 Master Wallet Setup Tool\n');
    console.log('Usage:');
    console.log('  node scripts/setup-master-wallet.js create   - Generate new master wallet');
    console.log('  node scripts/setup-master-wallet.js encrypt  - Encrypt existing secret key\n');
  }
}

main().catch(console.error);
