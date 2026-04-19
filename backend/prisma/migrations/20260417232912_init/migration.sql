/*
  Warnings:

  - The values [swap] on the enum `TransactionType` will be removed. If these variants are still used in the database, this will fail.
  - You are about to drop the column `btcTxHash` on the `Transaction` table. All the data in the column will be lost.
  - You are about to drop the column `evmTxHash` on the `Transaction` table. All the data in the column will be lost.
  - You are about to drop the column `isSwap` on the `Transaction` table. All the data in the column will be lost.
  - You are about to drop the column `solanaTxHash` on the `Transaction` table. All the data in the column will be lost.
  - You are about to drop the column `swapFromAsset` on the `Transaction` table. All the data in the column will be lost.
  - You are about to drop the column `swapQuoteId` on the `Transaction` table. All the data in the column will be lost.
  - You are about to drop the column `swapToAsset` on the `Transaction` table. All the data in the column will be lost.
  - You are about to drop the column `btcPublicKey` on the `User` table. All the data in the column will be lost.
  - You are about to drop the column `btcSecretKey` on the `User` table. All the data in the column will be lost.
  - You are about to drop the column `evmPublicKey` on the `User` table. All the data in the column will be lost.
  - You are about to drop the column `evmSecretKey` on the `User` table. All the data in the column will be lost.
  - You are about to drop the column `solanaPublicKey` on the `User` table. All the data in the column will be lost.
  - You are about to drop the column `solanaSecretKey` on the `User` table. All the data in the column will be lost.

*/
-- AlterEnum
BEGIN;
CREATE TYPE "TransactionType_new" AS ENUM ('send', 'receive');
ALTER TABLE "Transaction" ALTER COLUMN "type" TYPE "TransactionType_new" USING ("type"::text::"TransactionType_new");
ALTER TYPE "TransactionType" RENAME TO "TransactionType_old";
ALTER TYPE "TransactionType_new" RENAME TO "TransactionType";
DROP TYPE "TransactionType_old";
COMMIT;

-- DropIndex
DROP INDEX "Transaction_btcTxHash_key";

-- DropIndex
DROP INDEX "Transaction_evmTxHash_key";

-- DropIndex
DROP INDEX "Transaction_network_idx";

-- DropIndex
DROP INDEX "Transaction_solanaTxHash_key";

-- DropIndex
DROP INDEX "User_btcPublicKey_idx";

-- DropIndex
DROP INDEX "User_btcPublicKey_key";

-- DropIndex
DROP INDEX "User_evmPublicKey_idx";

-- DropIndex
DROP INDEX "User_evmPublicKey_key";

-- DropIndex
DROP INDEX "User_solanaPublicKey_idx";

-- DropIndex
DROP INDEX "User_solanaPublicKey_key";

-- AlterTable
ALTER TABLE "Transaction" DROP COLUMN "btcTxHash",
DROP COLUMN "evmTxHash",
DROP COLUMN "isSwap",
DROP COLUMN "solanaTxHash",
DROP COLUMN "swapFromAsset",
DROP COLUMN "swapQuoteId",
DROP COLUMN "swapToAsset";

-- AlterTable
ALTER TABLE "User" DROP COLUMN "btcPublicKey",
DROP COLUMN "btcSecretKey",
DROP COLUMN "evmPublicKey",
DROP COLUMN "evmSecretKey",
DROP COLUMN "solanaPublicKey",
DROP COLUMN "solanaSecretKey";

-- CreateIndex
CREATE INDEX "Transaction_asset_idx" ON "Transaction"("asset");
