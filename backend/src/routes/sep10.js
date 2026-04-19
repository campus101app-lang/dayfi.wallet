// src/routes/sep10.js
// SEP-10: Stellar Web Authentication
// https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0010.md

import express from 'express';
import StellarSdk from '@stellar/stellar-sdk';
import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';
dotenv.config();

const router = express.Router();

const networkPassphrase = process.env.STELLAR_NETWORK !== 'mainnet'
  ? StellarSdk.Networks.TESTNET
  : StellarSdk.Networks.PUBLIC;

// Server signing keypair — generate once and store in .env as ANCHOR_SECRET_KEY
const anchorKeypair = StellarSdk.Keypair.fromSecret(
  process.env.ANCHOR_SECRET_KEY || StellarSdk.Keypair.random().secret()
);

const WEB_AUTH_DOMAIN = process.env.WEB_AUTH_DOMAIN || 'api.dayfi.me';
const HOME_DOMAIN     = process.env.HOME_DOMAIN     || 'dayfi.me';

// GET /sep10/auth?account=G...
// Returns a challenge transaction for the client to sign
router.get('/auth', async (req, res) => {
  const { account, memo, home_domain } = req.query;

  if (!account) {
    return res.status(400).json({ error: 'account parameter required' });
  }

  if (!/^G[A-Z0-9]{55}$/.test(account)) {
    return res.status(400).json({ error: 'Invalid Stellar account address' });
  }

  try {
    // Load or create a nonce account for the challenge
    // SEP-10 uses a random keypair as the "client" in the challenge tx
    const nonce = StellarSdk.Keypair.random();

    // The challenge tx must be signed by the anchor's key
    // and must have a manage_data operation with the home domain
    const now = Math.floor(Date.now() / 1000);
    const expiration = now + 300; // 5 minute window

    // Build challenge transaction
    // Per SEP-10, use a server account with sequence 0
    const serverAccount = new StellarSdk.Account(anchorKeypair.publicKey(), '-1');

    const tx = new StellarSdk.TransactionBuilder(serverAccount, {
      fee: '100',
      networkPassphrase,
      timebounds: { minTime: now, maxTime: expiration },
    })
      // First op: manage_data from the client account proving ownership
      .addOperation(
        StellarSdk.Operation.manageData({
          name: `${HOME_DOMAIN} auth`,
          value: Buffer.from(nonce.publicKey()),
          source: account,
        })
      )
      // Second op: manage_data from server proving it's the right anchor
      .addOperation(
        StellarSdk.Operation.manageData({
          name: 'web_auth_domain',
          value: Buffer.from(WEB_AUTH_DOMAIN),
          source: anchorKeypair.publicKey(),
        })
      )
      .build();

    // Server signs the challenge
    tx.sign(anchorKeypair);

    res.json({
      transaction: tx.toEnvelope().toXDR('base64'),
      network_passphrase: networkPassphrase,
    });
  } catch (err) {
    console.error('SEP-10 challenge error:', err);
    res.status(500).json({ error: 'Failed to generate challenge' });
  }
});

// POST /sep10/auth
// Client submits the challenge signed by their key -> returns JWT
router.post('/auth', async (req, res) => {
  const { transaction } = req.body;

  if (!transaction) {
    return res.status(400).json({ error: 'transaction required' });
  }

  try {
    // Decode and validate the submitted transaction
    const envelope = StellarSdk.xdr.TransactionEnvelope.fromXDR(transaction, 'base64');
    const tx = new StellarSdk.Transaction(envelope, networkPassphrase);

    // Validate timebounds
    const now = Math.floor(Date.now() / 1000);
    if (tx.timeBounds) {
      if (now < parseInt(tx.timeBounds.minTime) || now > parseInt(tx.timeBounds.maxTime)) {
        return res.status(400).json({ error: 'Transaction expired or not yet valid' });
      }
    }

    // Get client account from first operation's source
    const firstOp = tx.operations[0];
    if (!firstOp || firstOp.type !== 'manageData') {
      return res.status(400).json({ error: 'Invalid challenge transaction' });
    }

    const clientAccount = firstOp.source;
    if (!clientAccount) {
      return res.status(400).json({ error: 'Missing client account in transaction' });
    }

    // Verify signatures: must have anchor signature + client signature
    const signatures = tx.signatures;
    if (signatures.length < 2) {
      return res.status(400).json({ error: 'Transaction must be signed by client' });
    }

    // Verify anchor signed it
    const txHash = tx.hash();
    const anchorSig = signatures.find(sig => {
      try {
        return anchorKeypair.verify(txHash, sig.signature());
      } catch { return false; }
    });

    if (!anchorSig) {
      return res.status(400).json({ error: 'Missing anchor signature' });
    }

    // Verify client signed it
    const clientKeypair = StellarSdk.Keypair.fromPublicKey(clientAccount);
    const clientSig = signatures.find(sig => {
      try {
        return clientKeypair.verify(txHash, sig.signature());
      } catch { return false; }
    });

    if (!clientSig) {
      return res.status(400).json({ error: 'Missing client signature' });
    }

    // Issue SEP-10 JWT
    const sep10Token = jwt.sign(
      {
        iss: `https://${HOME_DOMAIN}`,
        sub: clientAccount,
        iat: now,
        exp: now + 24 * 60 * 60, // 24 hours
      },
      process.env.JWT_SECRET,
      { algorithm: 'HS256' }
    );

    res.json({ token: sep10Token });
  } catch (err) {
    console.error('SEP-10 verify error:', err);
    res.status(400).json({ error: 'Invalid transaction: ' + err.message });
  }
});

export { anchorKeypair };
export default router;
