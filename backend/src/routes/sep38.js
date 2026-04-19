// src/routes/sep38.js
// SEP-38: Anchor RFQ (Request for Quote)
// https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0038.md

import express from 'express';
import jwt from 'jsonwebtoken';

const router = express.Router();

const USDC_ISSUER = process.env.USDC_ISSUER || 'GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5';
const BTC_ISSUER  = process.env.BTC_ISSUER  || 'GDPJALI4AZKUU2W426U5WKMAT6CN3AJRPIIRYR2YM54TL2GDWO5O2MZM';
const GOLD_ISSUER = process.env.GOLD_ISSUER || 'GDPJALI4AZKUU2W426U5WKMAT6CN3AJRPIIRYR2YM54TL2GDWO5O2MZM';

// Asset identifiers in SEP-38 format: stellar:<code>:<issuer>
const STELLAR_ASSETS = {
  [`stellar:USDC:${USDC_ISSUER}`]: { code: 'USDC', decimals: 2 },
  [`stellar:BTC:${BTC_ISSUER}`]:   { code: 'BTC',  decimals: 8 },
  [`stellar:GOLD:${GOLD_ISSUER}`]: { code: 'GOLD', decimals: 4 },
  'stellar:native':                 { code: 'XLM',  decimals: 7 },
};

// Mock price feed — replace with real oracle/exchange API
async function getPrice(fromAsset, toAsset) {
  // In production: fetch from CoinGecko, Binance, or your price feed
  const prices = {
    'BTC/USDC':  95000,
    'GOLD/USDC': 3200,
    'XLM/USDC':  0.11,
    'USDC/BTC':  1 / 95000,
    'USDC/GOLD': 1 / 3200,
    'USDC/XLM':  1 / 0.11,
  };

  const from = STELLAR_ASSETS[fromAsset]?.code;
  const to   = STELLAR_ASSETS[toAsset]?.code;

  if (!from || !to) return null;
  if (from === to) return 1;

  const key = `${from}/${to}`;
  return prices[key] || (prices[`${to}/${from}`] ? 1 / prices[`${to}/${from}`] : null);
}

// GET /sep38/info
router.get('/info', (req, res) => {
  res.json({
    assets: Object.entries(STELLAR_ASSETS).map(([id, info]) => ({
      asset: id,
      country_codes: ['NG', 'GH', 'KE', 'US', 'GB'],
      sell_delivery_methods: [
        { name: 'bank_transfer', description: 'Bank transfer (local)' },
        { name: 'mobile_money', description: 'Mobile money (MTN, Airtel)' },
      ],
      buy_delivery_methods: [
        { name: 'bank_transfer', description: 'Bank transfer (local)' },
        { name: 'mobile_money', description: 'Mobile money (MTN, Airtel)' },
        { name: 'card', description: 'Credit/Debit card' },
      ],
    })),
  });
});

// GET /sep38/prices?sell_asset=...&sell_amount=...&buy_assets=...
// Returns prices for converting one asset to others
router.get('/prices', async (req, res) => {
  const { sell_asset, sell_amount, buy_assets, country_code, buy_delivery_method } = req.query;

  if (!sell_asset || !sell_amount) {
    return res.status(400).json({ error: 'sell_asset and sell_amount required' });
  }

  const sellInfo = STELLAR_ASSETS[sell_asset];
  if (!sellInfo) {
    return res.status(400).json({ error: 'Unsupported sell_asset' });
  }

  const buyAssetList = buy_assets
    ? buy_assets.split(',')
    : Object.keys(STELLAR_ASSETS).filter(a => a !== sell_asset);

  try {
    const buyPrices = [];

    for (const buyAsset of buyAssetList) {
      const price = await getPrice(sell_asset, buyAsset);
      if (price === null) continue;

      const buyInfo = STELLAR_ASSETS[buyAsset];
      const buyAmount = (parseFloat(sell_amount) * price).toFixed(buyInfo?.decimals || 2);
      const fee = (parseFloat(sell_amount) * 0.001).toFixed(sellInfo.decimals); // 0.1% fee

      buyPrices.push({
        asset: buyAsset,
        price: price.toFixed(8),
        decimals: buyInfo?.decimals || 2,
        buy_amount: buyAmount,
        fee: {
          total: fee,
          asset: sell_asset,
        },
      });
    }

    res.json({ buy_assets: buyPrices });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /sep38/price?sell_asset=...&buy_asset=...&sell_amount=...
// Returns a single price quote
router.get('/price', async (req, res) => {
  const { sell_asset, buy_asset, sell_amount, buy_amount, context } = req.query;

  if (!sell_asset || !buy_asset) {
    return res.status(400).json({ error: 'sell_asset and buy_asset required' });
  }
  if (!sell_amount && !buy_amount) {
    return res.status(400).json({ error: 'sell_amount or buy_amount required' });
  }

  try {
    const price = await getPrice(sell_asset, buy_asset);
    if (price === null) {
      return res.status(400).json({ error: 'Cannot get price for this pair' });
    }

    const sellInfo = STELLAR_ASSETS[sell_asset];
    const buyInfo  = STELLAR_ASSETS[buy_asset];

    let computedSellAmount, computedBuyAmount;

    if (sell_amount) {
      computedSellAmount = parseFloat(sell_amount);
      computedBuyAmount  = computedSellAmount * price;
    } else {
      computedBuyAmount  = parseFloat(buy_amount);
      computedSellAmount = computedBuyAmount / price;
    }

    const fee = computedSellAmount * 0.001; // 0.1%
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 min validity

    res.json({
      sell_asset,
      buy_asset,
      sell_amount: (computedSellAmount - fee).toFixed(sellInfo?.decimals || 2),
      buy_amount:  computedBuyAmount.toFixed(buyInfo?.decimals || 2),
      price:       price.toFixed(8),
      total_price: (computedBuyAmount / computedSellAmount).toFixed(8),
      fee: {
        total:   fee.toFixed(sellInfo?.decimals || 2),
        asset:   sell_asset,
        details: [{ name: 'DayFi service fee (0.1%)', amount: fee.toFixed(sellInfo?.decimals || 2) }],
      },
      expires_at: expiresAt.toISOString(),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /sep38/quote
// Returns a firm quote (requires auth)
router.post('/quote', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(403).json({ error: 'Authentication required' });
  }

  const { sell_asset, buy_asset, sell_amount, buy_amount, expire_after, context } = req.body;

  if (!sell_asset || !buy_asset || (!sell_amount && !buy_amount)) {
    return res.status(400).json({ error: 'sell_asset, buy_asset, and amount required' });
  }

  try {
    const price = await getPrice(sell_asset, buy_asset);
    if (price === null) {
      return res.status(400).json({ error: 'Cannot quote this pair' });
    }

    const sellInfo = STELLAR_ASSETS[sell_asset];
    const buyInfo  = STELLAR_ASSETS[buy_asset];

    let computedSellAmount, computedBuyAmount;
    if (sell_amount) {
      computedSellAmount = parseFloat(sell_amount);
      computedBuyAmount  = computedSellAmount * price;
    } else {
      computedBuyAmount  = parseFloat(buy_amount);
      computedSellAmount = computedBuyAmount / price;
    }

    const fee = computedSellAmount * 0.001;
    const quoteId = `q_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 min

    res.json({
      id: quoteId,
      expires_at: expiresAt.toISOString(),
      price:       price.toFixed(8),
      sell_asset,
      sell_amount: computedSellAmount.toFixed(sellInfo?.decimals || 2),
      buy_asset,
      buy_amount:  computedBuyAmount.toFixed(buyInfo?.decimals || 2),
      fee: {
        total: fee.toFixed(sellInfo?.decimals || 2),
        asset: sell_asset,
      },
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

export default router;
