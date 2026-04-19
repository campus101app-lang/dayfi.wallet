/*
  Warnings:

  - You are about to drop the `device_tokens` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `transactions` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `username_reservations` table. If the table is not empty, all the data it contains will be lost.
  - You are about to drop the `users` table. If the table is not empty, all the data it contains will be lost.

*/
-- CreateEnum
CREATE TYPE "TransactionType" AS ENUM ('send', 'receive', 'swap');

-- CreateEnum
CREATE TYPE "TransactionStatus" AS ENUM ('pending', 'confirmed', 'failed');

-- DropForeignKey
ALTER TABLE "device_tokens" DROP CONSTRAINT "device_tokens_userId_fkey";

-- DropForeignKey
ALTER TABLE "transactions" DROP CONSTRAINT "transactions_userId_fkey";

-- DropTable
DROP TABLE "device_tokens";

-- DropTable
DROP TABLE "transactions";

-- DropTable
DROP TABLE "username_reservations";

-- DropTable
DROP TABLE "users";

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "isVerified" BOOLEAN NOT NULL DEFAULT false,
    "otpCode" TEXT,
    "otpExpiry" TIMESTAMP(3),
    "otpAttempts" INTEGER NOT NULL DEFAULT 0,
    "stellarPublicKey" TEXT,
    "stellarSecretKey" TEXT,
    "evmPublicKey" TEXT,
    "evmSecretKey" TEXT,
    "btcPublicKey" TEXT,
    "btcSecretKey" TEXT,
    "solanaPublicKey" TEXT,
    "solanaSecretKey" TEXT,
    "faceIdEnabled" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "lastLoginAt" TIMESTAMP(3),

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Transaction" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "TransactionType" NOT NULL,
    "status" "TransactionStatus" NOT NULL DEFAULT 'pending',
    "amount" DOUBLE PRECISION NOT NULL,
    "asset" TEXT NOT NULL,
    "network" TEXT NOT NULL DEFAULT 'stellar',
    "fromAddress" TEXT,
    "toAddress" TEXT,
    "toUsername" TEXT,
    "stellarTxHash" TEXT,
    "evmTxHash" TEXT,
    "btcTxHash" TEXT,
    "solanaTxHash" TEXT,
    "memo" TEXT,
    "fee" DOUBLE PRECISION,
    "isSwap" BOOLEAN NOT NULL DEFAULT false,
    "swapFromAsset" TEXT,
    "swapToAsset" TEXT,
    "swapQuoteId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Transaction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeviceToken" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DeviceToken_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- CreateIndex
CREATE UNIQUE INDEX "User_stellarPublicKey_key" ON "User"("stellarPublicKey");

-- CreateIndex
CREATE UNIQUE INDEX "User_evmPublicKey_key" ON "User"("evmPublicKey");

-- CreateIndex
CREATE UNIQUE INDEX "User_btcPublicKey_key" ON "User"("btcPublicKey");

-- CreateIndex
CREATE UNIQUE INDEX "User_solanaPublicKey_key" ON "User"("solanaPublicKey");

-- CreateIndex
CREATE INDEX "User_email_idx" ON "User"("email");

-- CreateIndex
CREATE INDEX "User_username_idx" ON "User"("username");

-- CreateIndex
CREATE INDEX "User_stellarPublicKey_idx" ON "User"("stellarPublicKey");

-- CreateIndex
CREATE INDEX "User_evmPublicKey_idx" ON "User"("evmPublicKey");

-- CreateIndex
CREATE INDEX "User_btcPublicKey_idx" ON "User"("btcPublicKey");

-- CreateIndex
CREATE INDEX "User_solanaPublicKey_idx" ON "User"("solanaPublicKey");

-- CreateIndex
CREATE UNIQUE INDEX "Transaction_stellarTxHash_key" ON "Transaction"("stellarTxHash");

-- CreateIndex
CREATE UNIQUE INDEX "Transaction_evmTxHash_key" ON "Transaction"("evmTxHash");

-- CreateIndex
CREATE UNIQUE INDEX "Transaction_btcTxHash_key" ON "Transaction"("btcTxHash");

-- CreateIndex
CREATE UNIQUE INDEX "Transaction_solanaTxHash_key" ON "Transaction"("solanaTxHash");

-- CreateIndex
CREATE INDEX "Transaction_userId_idx" ON "Transaction"("userId");

-- CreateIndex
CREATE INDEX "Transaction_createdAt_idx" ON "Transaction"("createdAt");

-- CreateIndex
CREATE INDEX "Transaction_network_idx" ON "Transaction"("network");

-- CreateIndex
CREATE UNIQUE INDEX "DeviceToken_token_key" ON "DeviceToken"("token");

-- CreateIndex
CREATE INDEX "DeviceToken_userId_idx" ON "DeviceToken"("userId");

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeviceToken" ADD CONSTRAINT "DeviceToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
