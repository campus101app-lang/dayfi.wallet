-- CreateEnum
CREATE TYPE IF NOT EXISTS "FwPaymentType" AS ENUM ('deposit', 'withdrawal');

-- CreateEnum
CREATE TYPE IF NOT EXISTS "FwPaymentStatus" AS ENUM ('initiated', 'pending', 'successful', 'failed');

-- AlterEnum
ALTER TYPE "TransactionType" ADD VALUE IF NOT EXISTS 'fiatDeposit';
ALTER TYPE "TransactionType" ADD VALUE IF NOT EXISTS 'fiatWithdrawal';

-- AlterTable
ALTER TABLE "Transaction" ADD COLUMN IF NOT EXISTS "fiatAmount" DOUBLE PRECISION;
ALTER TABLE "Transaction" ADD COLUMN IF NOT EXISTS "fiatCurrency" TEXT;
ALTER TABLE "Transaction" ADD COLUMN IF NOT EXISTS "flutterwaveRef" TEXT;
ALTER TABLE "Transaction" ADD COLUMN IF NOT EXISTS "flutterwaveStatus" TEXT;
ALTER TABLE "Transaction" ADD COLUMN IF NOT EXISTS "swapId" TEXT;

-- AlterTable
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "fullName" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "virtualAccountBank" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "virtualAccountName" TEXT;
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "virtualAccountNumber" TEXT;

-- CreateTable
CREATE TABLE IF NOT EXISTS "FlutterwavePayment" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "txRef" TEXT NOT NULL,
    "flwRef" TEXT,
    "type" "FwPaymentType" NOT NULL,
    "fiatAmount" DOUBLE PRECISION NOT NULL,
    "onChainAmount" DOUBLE PRECISION,
    "currency" TEXT NOT NULL DEFAULT 'NGN',
    "status" "FwPaymentStatus" NOT NULL DEFAULT 'initiated',
    "providerStatus" TEXT,
    "providerMessage" TEXT,
    "retryCount" INTEGER NOT NULL DEFAULT 0,
    "lastRetriedAt" TIMESTAMP(3),
    "idempotencyKey" TEXT,
    "bankCode" TEXT,
    "accountNumber" TEXT,
    "accountName" TEXT,
    "customerEmail" TEXT,
    "customerName" TEXT,
    "redirectUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FlutterwavePayment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "FlutterwavePayment_txRef_key" ON "FlutterwavePayment"("txRef");
CREATE INDEX IF NOT EXISTS "FlutterwavePayment_userId_idx" ON "FlutterwavePayment"("userId");
CREATE INDEX IF NOT EXISTS "FlutterwavePayment_txRef_idx" ON "FlutterwavePayment"("txRef");
CREATE INDEX IF NOT EXISTS "FlutterwavePayment_flwRef_idx" ON "FlutterwavePayment"("flwRef");
CREATE INDEX IF NOT EXISTS "FlutterwavePayment_idempotencyKey_idx" ON "FlutterwavePayment"("idempotencyKey");

-- AddForeignKey
ALTER TABLE "FlutterwavePayment" DROP CONSTRAINT IF EXISTS "FlutterwavePayment_userId_fkey";
ALTER TABLE "FlutterwavePayment" ADD CONSTRAINT "FlutterwavePayment_userId_fkey" 
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;import { PrismaClient } from "@prisma/client";
