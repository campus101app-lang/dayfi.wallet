// src/routes/toml.js
// SEP-01: Stellar Info File
// Served at https://dayfi.me/.well-known/stellar.toml

import express from 'express';
import { anchorKeypair } from './sep10.js';

const router = express.Router();

const USDC_ISSUER = process.env.USDC_ISSUER || 'GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5';
const BTC_ISSUER  = process.env.BTC_ISSUER  || 'GDPJALI4AZKUU2W426U5WKMAT6CN3AJRPIIRYR2YM54TL2GDWO5O2MZM';
const GOLD_ISSUER = process.env.GOLD_ISSUER || 'GDPJALI4AZKUU2W426U5WKMAT6CN3AJRPIIRYR2YM54TL2GDWO5O2MZM';

const HOME_DOMAIN     = process.env.HOME_DOMAIN     || 'dayfi.me';
const API_DOMAIN      = process.env.API_DOMAIN      || 'api.dayfi.me';
const WEB_AUTH_DOMAIN = process.env.WEB_AUTH_DOMAIN || 'api.dayfi.me';
const NETWORK         = process.env.STELLAR_NETWORK || 'testnet';

// GET /.well-known/stellar.toml
router.get('/stellar.toml', (req, res) => {
  res.setHeader('Content-Type', 'text/plain');
  res.setHeader('Access-Control-Allow-Origin', '*');

  const toml = `
# DayFi Stellar Anchor Configuration
# SEP-01: https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0001.md

VERSION = "2.0.0"

NETWORK_PASSPHRASE = "${NETWORK === 'mainnet'
  ? 'Public Global Stellar Network ; September 2015'
  : 'Test SDF Network ; September 2015'}"

HOME_DOMAIN = "${HOME_DOMAIN}"

SIGNING_KEY = "${anchorKeypair.publicKey()}"

HORIZON_URL = "${process.env.STELLAR_HORIZON_URL || 'https://horizon-testnet.stellar.org'}"

# Supported SEPs
SUPPORTED_SEPS = [1, 6, 10, 12, 24, 38]

# ─── Service Documentation ────────────────────────────────

[DOCUMENTATION]
ORG_NAME = "DayFi"
ORG_URL = "https://${HOME_DOMAIN}"
ORG_DESCRIPTION = "DayFi — Send money with just a username. USDC, BTC, GOLD, and XLM on Stellar."
ORG_LOGO = "https://${HOME_DOMAIN}/logo.png"
ORG_SUPPORT_EMAIL = "support@${HOME_DOMAIN}"
ORG_GITHUB = "https://github.com/dayfi"
ORG_OFFICIAL_SUPPORT_CHANNELS = [{type = "email", contact = "support@${HOME_DOMAIN}"}]

# ─── Principals ───────────────────────────────────────────

[[PRINCIPALS]]
name = "DayFi Support"
email = "support@${HOME_DOMAIN}"

# ─── Currencies ───────────────────────────────────────────

[[CURRENCIES]]
code = "USDC"
issuer = "${USDC_ISSUER}"
display_decimals = 2
name = "USD Coin"
desc = "Circle's USDC stablecoin on Stellar. 1 USDC = 1 USD."
image = "https://${HOME_DOMAIN}/assets/usdc.png"
is_asset_anchored = true
anchor_asset_type = "fiat"
anchor_asset = "USD"
status = "live"
regulated = false

[[CURRENCIES]]
code = "BTC"
issuer = "${BTC_ISSUER}"
display_decimals = 8
name = "Bitcoin"
desc = "Tokenized Bitcoin on Stellar. Backed 1:1 by BTC."
image = "https://${HOME_DOMAIN}/assets/btc.png"
is_asset_anchored = true
anchor_asset_type = "crypto"
anchor_asset = "BTC"
status = "live"
regulated = false

[[CURRENCIES]]
code = "GOLD"
issuer = "${GOLD_ISSUER}"
display_decimals = 4
name = "Tether Gold"
desc = "Gold-backed token on Stellar. Each token represents 1 troy ounce of gold."
image = "https://${HOME_DOMAIN}/assets/gold.png"
is_asset_anchored = true
anchor_asset_type = "commodity"
anchor_asset = "Gold"
status = "live"
regulated = true

# ─── Validators ───────────────────────────────────────────
# (Add if you run a Stellar validator node)

# ─── SEP Service Endpoints ────────────────────────────────

[WEB_AUTH_ENDPOINT]
WEB_AUTH_ENDPOINT = "https://${API_DOMAIN}/sep10/auth"

[TRANSFER_SERVER_SEP0024]
TRANSFER_SERVER_SEP0024 = "https://${API_DOMAIN}/sep24"

[ANCHOR_QUOTE_SERVER]
ANCHOR_QUOTE_SERVER = "https://${API_DOMAIN}/sep38"

[KYC_SERVER]
KYC_SERVER = "https://${API_DOMAIN}/sep12"
`.trim();

  res.send(toml);
});

export default router;
