import StellarSdk from "@stellar/stellar-sdk";
import StellarHDWallet from "stellar-hd-wallet";
import crypto from "crypto";
import { PrismaClient } from "@prisma/client";
import {
  sendPaymentSentEmail,
  sendPaymentReceivedEmail,
  sendSwapCompleteEmail,
} from "./emailService.js";

const prisma = new PrismaClient();

const isTestnet = process.env.STELLAR_NETWORK !== "mainnet";
const server = new StellarSdk.Horizon.Server(
  process.env.STELLAR_HORIZON_URL ||
    (isTestnet
      ? "https://horizon-testnet.stellar.org"
      : "https://horizon.stellar.org"),
);
const networkPassphrase = isTestnet
  ? StellarSdk.Networks.TESTNET
  : StellarSdk.Networks.PUBLIC;

// ─── Issuer Validation Helper ────────────────────────────────────────────────
// Prevents the "Issuer is invalid" crash by ensuring the string is a
// valid Stellar G-address (56 chars) before passing it to the SDK.
const isValidAddress = (addr) => {
  if (typeof addr !== "string") return false;
  const cleanAddr = addr.replace(/[\n\r\s\t]/g, ""); // Strips newlines, returns, spaces, tabs
  return /^G[A-Z0-9]{55}$/.test(cleanAddr);
};

// ─── Issuers ──────────────────────────────────────────────────────────────────

export const ISSUERS = {
  USDC: isValidAddress(process.env.USDC_ISSUER)
    ? process.env.USDC_ISSUER
    : "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN",

  EURC: isValidAddress(process.env.EURC_ISSUER)
    ? process.env.EURC_ISSUER
    : "GDHU6WRG4IEQXM5NZ4BMPKOXHW76MZM4Y2IEMFDVXBSDP6SJY4ITNPP",

  PYUSD: isValidAddress(process.env.PYUSD_ISSUER)
    ? process.env.PYUSD_ISSUER
    : "GDQE7IXJ4HUHV6RQHIUPRJSEZE4DRS5WY577O2FY6YQ5LVWZ7JZTU2V5",

  BENJI: isValidAddress(process.env.BENJI_ISSUER)
    ? process.env.BENJI_ISSUER
    : "GBHNGLLIE3KWGKCHIKMHJ5HVZHYIK7WTBE4QF5PLAKL4CJGSEU7HZIW5",

  USDY: isValidAddress(process.env.USDY_ISSUER)
    ? process.env.USDY_ISSUER
    : "GAJMPX5NBOG6TQFPQGRABJEEB2YE7RFRLUKJDZAZGAD5GFX4J7TADAZ6",

  WTGOLD: isValidAddress(process.env.WTGOLD_ISSUER)
    ? process.env.WTGOLD_ISSUER
    : "GAGMKQSAJBRDSVKZFBHRWWQDLT2QNDZ5ZGZF63QNSYDNQ6XFZEWSHKI",
};

// ─── Asset Objects ────────────────────────────────────────────────────────────

const safeAsset = (code, issuer) => {
  if (!isValidAddress(issuer)) {
    console.error(
      `❌ CRITICAL: ${code}_ISSUER is invalid! Using XLM fallback to prevent crash.`,
    );
    return StellarSdk.Asset.native();
  }
  return new StellarSdk.Asset(code, issuer);
};

export const ASSETS = {
  USDC: safeAsset("USDC", ISSUERS.USDC),
  EURC: safeAsset("EURC", ISSUERS.EURC),
  PYUSD: safeAsset("PYUSD", ISSUERS.PYUSD),
  BENJI: safeAsset("BENJI", ISSUERS.BENJI),
  USDY: safeAsset("USDY", ISSUERS.USDY),
  WTGOLD: safeAsset("WTGOLD", ISSUERS.WTGOLD),
  XLM: StellarSdk.Asset.native(),
};

export const SUPPORTED_ASSETS = [
  "USDC",
  "XLM",
  "EURC",
  "PYUSD",
  "BENJI",
  "USDY",
  "WTGOLD",
];

// ─── Encryption ───────────────────────────────────────────────────────────────

const ALGORITHM = "aes-256-gcm";
const ENCRYPTION_KEY = Buffer.from(
  process.env.WALLET_ENCRYPTION_KEY || "a".repeat(64),
  "hex",
);

function encrypt(text) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
  let enc = cipher.update(text, "utf8", "hex");
  enc += cipher.final("hex");
  return `${iv.toString("hex")}:${cipher.getAuthTag().toString("hex")}:${enc}`;
}

function decrypt(encText) {
  const [ivHex, tagHex, enc] = encText.split(":");
  const decipher = crypto.createDecipheriv(
    ALGORITHM,
    ENCRYPTION_KEY,
    Buffer.from(ivHex, "hex"),
  );
  decipher.setAuthTag(Buffer.from(tagHex, "hex"));
  let dec = decipher.update(enc, "hex", "utf8");
  dec += decipher.final("utf8");
  return dec;
}

// ─── Setup trustlines for user (after wallet is created) ─────────────────────

export async function setupUserTrustlines(user) {
  if (!user.stellarSecretKey) {
    console.warn(
      `⚠️  User ${user.id} has no secret key. Skipping trustline setup.`,
    );
    return false;
  }
  try {
    const secret = decrypt(user.stellarSecretKey);
    const keypair = StellarSdk.Keypair.fromSecret(secret);
    await addAllTrustlines(keypair);
    console.log(`✅ Trustlines added for ${user.stellarPublicKey}`);
    return true;
  } catch (err) {
    console.error(
      `❌ Trustline setup failed for user ${user.id}:`,
      err.message,
    );
    return false;
  }
}

// ─── Wallet creation (BIP-39, SEP-0005) ──────────────────────────────────────

export async function createStellarWallet() {
  const mnemonic = StellarHDWallet.generateMnemonic({ entropyBits: 128 });
  const wallet = StellarHDWallet.fromMnemonic(mnemonic);
  const keypair = wallet.getKeypair(0);
  const publicKey = keypair.publicKey();

  if (isTestnet) {
    try {
      const res = await fetch(
        `https://friendbot.stellar.org?addr=${encodeURIComponent(publicKey)}`,
      );
      if (res.ok) {
        console.log(`✅ Testnet funded: ${publicKey}`);
        await new Promise((r) => setTimeout(r, 3000));
        await addAllTrustlines(keypair);
      }
    } catch (err) {
      console.warn("Friendbot error:", err.message);
    }
  }

  return {
    publicKey,
    encryptedSecretKey: encrypt(keypair.secret()),
    encryptedMnemonic: encrypt(mnemonic),
  };
}

// ─── Trustlines ───────────────────────────────────────────────────────────────
// Batches all trustlines into a single transaction.
// Skips any that already exist so this is safe to call repeatedly.
// Each non-native trustline costs 0.5 XLM reserve — 6 assets = 3 XLM extra
// reserve on top of the base 0.5 XLM, so wallets need ~4 XLM to be comfortable.

export async function addAllTrustlines(keypair) {
  try {
    const account = await server.loadAccount(keypair.publicKey());

    const existingCodes = new Set(
      account.balances
        .filter((b) => b.asset_type !== "native")
        .map((b) => b.asset_code),
    );

    // Non-native assets needing trustlines
    const trustlineAssets = [
      { asset: ASSETS.USDC, limit: "1000000" },
      { asset: ASSETS.EURC, limit: "1000000" },
      { asset: ASSETS.PYUSD, limit: "1000000" },
      { asset: ASSETS.BENJI, limit: "100000" },
      { asset: ASSETS.USDY, limit: "100000" },
      { asset: ASSETS.WTGOLD, limit: "10000" },
    ];

    const missing = trustlineAssets.filter(
      ({ asset }) => !existingCodes.has(asset.code),
    );

    if (missing.length === 0) {
      console.log(`ℹ️  All trustlines already exist for ${keypair.publicKey()}`);
      return null;
    }

    const txBuilder = new StellarSdk.TransactionBuilder(account, {
      fee: String(parseInt(StellarSdk.BASE_FEE) * missing.length),
      networkPassphrase,
    });

    for (const { asset, limit } of missing) {
      txBuilder.addOperation(
        StellarSdk.Operation.changeTrust({ asset, limit }),
      );
    }

    const tx = txBuilder.setTimeout(30).build();
    tx.sign(keypair);
    const result = await server.submitTransaction(tx);
    console.log(
      `✅ Added ${missing.length} trustline(s): ${missing.map((m) => m.asset.code).join(", ")}`,
    );
    return result;
  } catch (err) {
    console.error("Trustline error:", err.message);
    throw err;
  }
}

// ─── Balances ─────────────────────────────────────────────────────────────────

export async function getWalletBalances(publicKey) {
  try {
    const horizonBase =
      process.env.STELLAR_HORIZON_URL ||
      (isTestnet
        ? "https://horizon-testnet.stellar.org"
        : "https://horizon.stellar.org");

    const res = await fetch(`${horizonBase}/accounts/${publicKey}`, {
      headers: { "Cache-Control": "no-cache", Pragma: "no-cache" },
    });

    if (res.status === 404) {
      return {
        USDC: 0,
        XLM: 0,
        EURC: 0,
        PYUSD: 0,
        BENJI: 0,
        USDY: 0,
        WTGOLD: 0,
      };
    }

    const account = await res.json();
    const balances = {
      USDC: 0,
      XLM: 0,
      EURC: 0,
      PYUSD: 0,
      BENJI: 0,
      USDY: 0,
      WTGOLD: 0,
    };

    for (const b of account.balances) {
      if (b.asset_type === "native") {
        balances.XLM = parseFloat(b.balance);
      } else if (b.asset_code === "USDC" && b.asset_issuer === ISSUERS.USDC) {
        balances.USDC = parseFloat(b.balance);
      } else if (b.asset_code === "EURC" && b.asset_issuer === ISSUERS.EURC) {
        balances.EURC = parseFloat(b.balance);
      } else if (b.asset_code === "PYUSD" && b.asset_issuer === ISSUERS.PYUSD) {
        balances.PYUSD = parseFloat(b.balance);
      } else if (b.asset_code === "BENJI" && b.asset_issuer === ISSUERS.BENJI) {
        balances.BENJI = parseFloat(b.balance);
      } else if (b.asset_code === "USDY" && b.asset_issuer === ISSUERS.USDY) {
        balances.USDY = parseFloat(b.balance);
      } else if (
        b.asset_code === "WTGOLD" &&
        b.asset_issuer === ISSUERS.WTGOLD
      ) {
        balances.WTGOLD = parseFloat(b.balance);
      }
    }

    return balances;
  } catch (err) {
    return { USDC: 0, XLM: 0, EURC: 0, PYUSD: 0, BENJI: 0, USDY: 0, WTGOLD: 0 };
  }
}

// ─── Live prices ─────────────────────────────────────────────────────────────
// BENJI ≈ $1 (money market fund, stable NAV)
// USDY  ≈ $1 (yield-bearing stable dollar)
// EURC  tracked via EUR/USD rate
// WTGOLD tracked via gold price per troy oz

async function getLivePrices() {
  try {
    const res = await fetch(
      "https://api.coingecko.com/api/v3/simple/price?ids=usd-coin,stellar,euro-coin,paypal-usd,wrapped-steth&vs_currencies=usd",
    );
    const data = await res.json();
    return {
      XLM: data["stellar"]?.usd ?? 0.169,
      USDC: data["usd-coin"]?.usd ?? 1.0,
      EURC: data["euro-coin"]?.usd ?? 1.08, // EUR/USD approx
      PYUSD: data["paypal-usd"]?.usd ?? 1.0,
      BENJI: 1.0, // Stable NAV — always $1
      USDY: 1.0, // Yield-bearing but pegged to $1
      WTGOLD: parseFloat(process.env.WTGOLD_PRICE_USD || "3200"), // ~troy oz price, update via env
    };
  } catch {
    return {
      XLM: 0.169,
      USDC: 1.0,
      EURC: 1.08,
      PYUSD: 1.0,
      BENJI: 1.0,
      USDY: 1.0,
      WTGOLD: 3200,
    };
  }
}

// ─── Mnemonic ─────────────────────────────────────────────────────────────────

export async function getMnemonic(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user?.encryptedMnemonic) throw new Error("No mnemonic found");
  return decrypt(user.encryptedMnemonic);
}

// ─── Mark backed up ───────────────────────────────────────────────────────────

export async function markAsBackedUp(userId) {
  return prisma.user.update({
    where: { id: userId },
    data: { isBackedUp: true },
  });
}

// ─── Send ─────────────────────────────────────────────────────────────────────

export async function sendAsset(
  fromUserId,
  toAddress,
  amount,
  assetCode,
  memo = "",
) {
  const asset =
    assetCode === "XLM" ? StellarSdk.Asset.native() : ASSETS[assetCode];
  if (!asset) throw new Error(`Unsupported asset: ${assetCode}`);

  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.stellarPublicKey || !sender?.stellarSecretKey)
    throw new Error("Stellar wallet not found");

  const keypair = StellarSdk.Keypair.fromSecret(
    decrypt(sender.stellarSecretKey),
  );
  let destinationPublicKey = toAddress;
  let destinationUsername = null;

  if (!/^G[A-Z0-9]{55}$/.test(toAddress)) {
    const username = toAddress
      .replace("@dayfi.me", "")
      .replace("@", "")
      .toLowerCase();
    const recipient = await prisma.user.findUnique({ where: { username } });
    if (!recipient?.stellarPublicKey) throw new Error(`@${username} not found`);
    destinationPublicKey = recipient.stellarPublicKey;
    destinationUsername = username;
  }

  const senderAccount = await server.loadAccount(sender.stellarPublicKey);
  const txBuilder = new StellarSdk.TransactionBuilder(senderAccount, {
    fee: StellarSdk.BASE_FEE,
    networkPassphrase,
  });

  let destExists = true;
  try {
    await server.loadAccount(destinationPublicKey);
  } catch {
    destExists = false;
  }

  if (!destExists) {
    txBuilder.addOperation(
      StellarSdk.Operation.createAccount({
        destination: destinationPublicKey,
        startingBalance: "1",
      }),
    );
  } else {
    txBuilder.addOperation(
      StellarSdk.Operation.payment({
        destination: destinationPublicKey,
        asset,
        amount: amount.toString(),
      }),
    );
  }

  if (memo) txBuilder.addMemo(StellarSdk.Memo.text(memo.substring(0, 28)));

  const tx = txBuilder.setTimeout(30).build();
  tx.sign(keypair);
  const result = await server.submitTransaction(tx);

  const txData = {
    userId: fromUserId,
    type: "send",
    status: "confirmed",
    amount: parseFloat(amount),
    asset: assetCode,
    network: "stellar",
    fromAddress: sender.stellarPublicKey,
    toAddress: destinationPublicKey,
    toUsername: destinationUsername,
    stellarTxHash: result.hash,
    memo: memo || null,
  };

  await prisma.transaction.create({ data: txData });

  if (destinationUsername) {
    const recipient = await prisma.user.findUnique({
      where: { username: destinationUsername },
    });
    if (recipient?.id) {
      await prisma.transaction.create({
        data: {
          userId: recipient.id,
          type: "receive",
          status: "confirmed",
          amount: parseFloat(amount),
          asset: assetCode,
          network: "stellar",
          fromAddress: sender.stellarPublicKey,
          toAddress: destinationPublicKey,
          toUsername: sender.username || null,
          stellarTxHash: result.hash,
          memo: memo || null,
        },
      });
    }
  }

  try {
    await sendPaymentSentEmail(
      sender.email,
      destinationUsername || destinationPublicKey,
      amount,
      assetCode,
      memo,
    );
    if (destinationUsername) {
      const recipient = await prisma.user.findUnique({
        where: { username: destinationUsername },
      });
      if (recipient?.email) {
        await sendPaymentReceivedEmail(
          recipient.email,
          sender.username || "Someone",
          amount,
          assetCode,
          memo,
        );
      }
    }
  } catch (err) {
    console.warn("⚠️  Transaction email failed:", err.message);
  }

  return { hash: result.hash, amount, asset: assetCode };
}

// ─── Path Payment (Swap) ──────────────────────────────────────────────────────

export async function swapAssets(
  fromUserId,
  fromAssetCode,
  toAssetCode,
  amount,
) {
  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.stellarPublicKey || !sender?.stellarSecretKey)
    throw new Error("Stellar wallet not found");

  const keypair = StellarSdk.Keypair.fromSecret(
    decrypt(sender.stellarSecretKey),
  );
  const account = await server.loadAccount(sender.stellarPublicKey);

  const xlmBalance = parseFloat(
    account.balances.find((b) => !b.asset_type || b.asset_type === "native")
      ?.balance || "0",
  );
  const numTrustlines = account.balances.filter(
    (b) => b.asset_type !== "native",
  ).length;

  console.log(
    `📋 Account state: Sequence=${account.sequenceNumber()}, XLM=${xlmBalance}, Trustlines=${numTrustlines}`,
  );

  const sendAsset =
    fromAssetCode === "XLM" ? StellarSdk.Asset.native() : ASSETS[fromAssetCode];
  const destAsset =
    toAssetCode === "XLM" ? StellarSdk.Asset.native() : ASSETS[toAssetCode];

  if (!sendAsset) throw new Error(`Unsupported asset: ${fromAssetCode}`);
  if (!destAsset) throw new Error(`Unsupported asset: ${toAssetCode}`);

  console.log(
    `🔄 SWAP: Finding path ${fromAssetCode} (${amount}) -> ${toAssetCode}`,
  );

  const paths = await server
    .strictSendPaths(sendAsset, amount.toString(), [destAsset])
    .call();

  if (!paths.records.length) {
    console.error(
      `❌ No liquidity path found: ${fromAssetCode} -> ${toAssetCode} for ${amount}`,
    );
    throw new Error("No liquidity found for swap.");
  }

  const bestPath = paths.records[0];
  const destMin = (parseFloat(bestPath.destination_amount) * 0.98).toFixed(7);

  const path = (bestPath.path || []).map((asset) => {
    if (asset.asset_type === "native") return StellarSdk.Asset.native();
    return new StellarSdk.Asset(asset.asset_code, asset.asset_issuer);
  });

  console.log(
    `✅ Path found: ${path.length} hops, Will receive ~${bestPath.destination_amount} ${toAssetCode}`,
  );

  const numOperations = 1;
  const totalFeeInStroops = numOperations * parseInt(StellarSdk.BASE_FEE);
  const txFeeInXLM = totalFeeInStroops / 10000000;

  const newTrustlinesNeeded = path.filter((p) => {
    const code = p.code || "XLM";
    return !account.balances.some((b) => (b.asset_code || "XLM") === code);
  }).length;

  const totalReserveNeeded = 0.5 * (1 + numTrustlines + newTrustlinesNeeded);
  const minXLMRequired = totalReserveNeeded + txFeeInXLM + 0.1;

  if (xlmBalance < minXLMRequired) {
    throw new Error(
      `Insufficient XLM for swap. Need: ${minXLMRequired.toFixed(8)} XLM, Have: ${xlmBalance.toFixed(8)} XLM.`,
    );
  }

  const tx = new StellarSdk.TransactionBuilder(account, {
    fee: String(totalFeeInStroops),
    networkPassphrase,
  })
    .addOperation(
      StellarSdk.Operation.pathPaymentStrictSend({
        sendAsset,
        sendAmount: parseFloat(amount).toFixed(7),
        destination: sender.stellarPublicKey,
        destAsset,
        destMin,
        path,
      }),
    )
    .setTimeout(30)
    .build();

  tx.sign(keypair);

  let result;
  try {
    result = await server.submitTransaction(tx);
  } catch (horizonErr) {
    const horizonResponse = horizonErr.response?.data;
    console.error(
      `❌ STELLAR REJECTED: ${horizonResponse?.title || "Unknown Error"}`,
    );
    console.error(
      "Stellar extras:",
      JSON.stringify(horizonResponse?.extras || {}, null, 2),
    );
    if (horizonResponse?.extras?.result_codes) {
      const codes = horizonResponse.extras.result_codes;
      throw new Error(
        `Stellar rejected: tx_code=${codes.transaction}, op_codes=[${(codes.operations || []).join(", ")}]`,
      );
    }
    throw horizonErr;
  }

  // Decode XDR to get exact received amount
  const resultXDR = StellarSdk.xdr.TransactionResult.fromXDR(
    result.result_xdr,
    "base64",
  );
  const actualReceivedRaw = resultXDR
    .result()
    .results()[0]
    .tr()
    .pathPaymentStrictSendResult()
    .success()
    .last()
    .amount()
    .toString();
  const actualReceived = parseFloat(actualReceivedRaw) / 10000000;

  console.log(
    `✅ Swap submitted: Hash ${result.hash} | Received: ${actualReceived} ${toAssetCode}`,
  );

  const swapId = `swap_${result.hash}_${Date.now()}`;

  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: "swap",
      status: "confirmed",
      amount: parseFloat(amount),
      asset: fromAssetCode,
      network: "stellar",
      fromAddress: sender.stellarPublicKey,
      toAddress: sender.stellarPublicKey,
      stellarTxHash: result.hash,
      isSwap: true,
      swapId,
      swapFromAsset: fromAssetCode,
      swapToAsset: toAssetCode,
      receivedAmount: actualReceived,
    },
  });

  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: "swap",
      status: "confirmed",
      amount: actualReceived,
      asset: toAssetCode,
      network: "stellar",
      fromAddress: sender.stellarPublicKey,
      toAddress: sender.stellarPublicKey,
      stellarTxHash: `${result.hash}_receive`,
      isSwap: true,
      swapId,
      swapFromAsset: fromAssetCode,
      swapToAsset: toAssetCode,
      receivedAmount: actualReceived,
    },
  });

  try {
    await sendSwapCompleteEmail(
      sender.email,
      fromAssetCode,
      toAssetCode,
      parseFloat(amount),
      actualReceived.toFixed(6),
    );
  } catch (err) {
    console.warn("⚠️  Swap email failed:", err.message);
  }

  return {
    hash: result.hash,
    fromAsset: fromAssetCode,
    toAsset: toAssetCode,
    sentAmount: parseFloat(amount),
    receivedAmount: actualReceived,
  };
}

// ─── Resolve username ─────────────────────────────────────────────────────────

export async function resolveUsername(username) {
  const lower = username
    .replace("@dayfi.me", "")
    .replace("@", "")
    .toLowerCase();
  const user = await prisma.user.findUnique({
    where: { username: lower },
    select: { username: true, stellarPublicKey: true },
  });
  if (!user?.stellarPublicKey) return null;
  return {
    username: `${user.username}@dayfi.me`,
    address: user.stellarPublicKey,
    network: "stellar",
  };
}

// ─── Transaction history ──────────────────────────────────────────────────────

export async function getStellarTransactions(publicKey, limit = 20) {
  try {
    const page = await server
      .transactions()
      .forAccount(publicKey)
      .limit(limit)
      .order("desc")
      .call();
    return page.records.map((tx) => ({
      hash: tx.hash,
      createdAt: tx.created_at,
      memo: tx.memo,
      successful: tx.successful,
    }));
  } catch {
    return [];
  }
}

// ─── Auto-fund new user wallets from master wallet ─────────────────────────

export async function fundNewUserWallet(userPublicKey, userId = null) {
  const masterPublicKey = process.env.MASTER_WALLET_PUBLIC_KEY;
  const masterSecretEncrypted = process.env.MASTER_WALLET_SECRET_KEY;
  const fundingAmount = process.env.FUNDING_AMOUNT || "5";

  if (!masterPublicKey || !masterSecretEncrypted) {
    console.warn("⚠️  Master wallet not configured. Skipping auto-funding.");
    return null;
  }

  try {
    const masterSecret = decrypt(masterSecretEncrypted);
    const masterKeypair = StellarSdk.Keypair.fromSecret(masterSecret);
    const masterAccount = await server.loadAccount(masterPublicKey);

    let destExists = true;
    try {
      await server.loadAccount(userPublicKey);
    } catch {
      destExists = false;
    }

    const txBuilder = new StellarSdk.TransactionBuilder(masterAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase,
    });

    if (!destExists) {
      txBuilder.addOperation(
        StellarSdk.Operation.createAccount({
          destination: userPublicKey,
          startingBalance: fundingAmount,
        }),
      );
    } else {
      txBuilder.addOperation(
        StellarSdk.Operation.payment({
          destination: userPublicKey,
          asset: StellarSdk.Asset.native(),
          amount: fundingAmount,
        }),
      );
    }

    const tx = txBuilder.setTimeout(30).build();
    tx.sign(masterKeypair);
    const result = await server.submitTransaction(tx);

    console.log(`✅ Funded ${userPublicKey} with ${fundingAmount} XLM`);

    if (userId) {
      await prisma.transaction.create({
        data: {
          userId,
          type: "receive",
          status: "confirmed",
          amount: parseFloat(fundingAmount),
          asset: "XLM",
          network: "stellar",
          fromAddress: masterPublicKey,
          toAddress: userPublicKey,
          stellarTxHash: result.hash,
          memo: "Initial account funding",
        },
      });
    }

    return result;
  } catch (err) {
    console.error("❌ Auto-funding failed:", err.message);
    return null;
  }
}

// ─── Send from Master Wallet (Admin) ──────────────────────────────────────────

export async function sendFromMasterWallet(
  recipientAddress,
  amount,
  memo = "",
) {
  const masterPublicKey = process.env.MASTER_WALLET_PUBLIC_KEY;
  const masterSecretEncrypted = process.env.MASTER_WALLET_SECRET_KEY;

  if (!masterPublicKey || !masterSecretEncrypted)
    throw new Error("Master wallet not configured");

  const amountNum = parseFloat(amount);
  if (isNaN(amountNum) || amountNum <= 0) throw new Error("Invalid amount");
  if (
    !recipientAddress ||
    recipientAddress.length !== 56 ||
    !recipientAddress.startsWith("G")
  )
    throw new Error("Invalid recipient address");

  try {
    const masterSecret = decrypt(masterSecretEncrypted);
    const masterKeypair = StellarSdk.Keypair.fromSecret(masterSecret);
    const masterAccount = await server.loadAccount(masterPublicKey);

    try {
      await server.loadAccount(recipientAddress);
    } catch {
      throw new Error("Recipient account does not exist on network");
    }

    const txBuilder = new StellarSdk.TransactionBuilder(masterAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase,
    });

    txBuilder.addOperation(
      StellarSdk.Operation.payment({
        destination: recipientAddress,
        asset: StellarSdk.Asset.native(),
        amount: amountNum.toString(),
      }),
    );

    if (memo) txBuilder.addMemo(StellarSdk.Memo.text(memo));

    const tx = txBuilder.setTimeout(30).build();
    tx.sign(masterKeypair);
    const result = await server.submitTransaction(tx);

    console.log(`✅ Sent ${amountNum} XLM from master to ${recipientAddress}`);
    return {
      success: true,
      hash: result.hash,
      amount: amountNum,
      recipient: recipientAddress,
      memo: memo || null,
    };
  } catch (err) {
    console.error("❌ Master send failed:", err.message);
    throw err;
  }
}

// ─── Sync blockchain transactions ──────────────────────────────────────────

export async function syncBlockchainTransactions(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user?.stellarPublicKey) throw new Error("User has no Stellar wallet");

  try {
    const page = await server
      .transactions()
      .forAccount(user.stellarPublicKey)
      .limit(50)
      .order("desc")
      .call();

    let synced = 0;
    for (const tx of page.records) {
      const existing = await prisma.transaction.findUnique({
        where: { stellarTxHash: tx.hash },
      });
      if (existing) continue;

      const ops = tx.operations();
      for (const op of ops) {
        if (
          op.type_code === "payment" ||
          op.type_code === "path_payment_strict_send"
        ) {
          if (
            op.to === user.stellarPublicKey ||
            op.destination === user.stellarPublicKey
          ) {
            const amount = parseFloat(op.amount || op.send_amount || 0);
            if (amount > 0) {
              let asset = "XLM";
              if (
                op.asset_type === "credit_alphanum4" ||
                op.asset_type === "credit_alphanum12"
              ) {
                asset = op.asset_code || "UNKNOWN";
              }
              await prisma.transaction.create({
                data: {
                  userId,
                  type: "receive",
                  status: "confirmed",
                  amount,
                  asset,
                  network: "stellar",
                  fromAddress: op.from,
                  toAddress: user.stellarPublicKey,
                  stellarTxHash: tx.hash,
                  memo: tx.memo || null,
                },
              });
              synced++;
            }
          }
        }
      }
    }

    console.log(`✅ Synced ${synced} transactions for user ${userId}`);
    return { synced };
  } catch (err) {
    console.error("❌ Sync failed:", err.message);
    throw err;
  }
}

export { server, networkPassphrase };
