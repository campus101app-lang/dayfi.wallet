#!/usr/bin/env node
import StellarSdk from '@stellar/stellar-sdk';
import crypto from 'crypto';
import dotenv from 'dotenv';

dotenv.config();

const ALGORITHM = 'aes-256-gcm';
const ENCRYPTION_KEY = Buffer.from(
  process.env.WALLET_ENCRYPTION_KEY || 'a'.repeat(64),
  'hex'
);

// Generate new keypair
const keypair = StellarSdk.Keypair.random();
const publicKey = keypair.publicKey();
const secretKey = keypair.secret();

console.log('\n🔐 NEW MASTER WALLET GENERATED\n');
console.log('═'.repeat(60));
console.log('📍 PUBLIC KEY (safe to share):');
console.log(publicKey);
console.log('\n🔑 SECRET KEY (SAVE THIS SAFELY!):');
console.log(secretKey);
console.log('═'.repeat(60));

// Encrypt for storage
const iv = crypto.randomBytes(16);
const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
let enc = cipher.update(secretKey, 'utf8', 'hex');
enc += cipher.final('hex');
const tag = cipher.getAuthTag();
const encrypted = `${iv.toString('hex')}:${tag.toString('hex')}:${enc}`;

console.log('\n📋 Add these to backend/.env:\n');
console.log(`MASTER_WALLET_PUBLIC_KEY=${publicKey}`);
console.log(`MASTER_WALLET_SECRET_KEY=${encrypted}`);
console.log('\n⚠️  IMPORTANT:');
console.log('1. Copy the SECRET KEY above and save it somewhere safe');
console.log('2. You need it to transfer funds into the wallet');
console.log('3. Never commit secrets to version control\n');
