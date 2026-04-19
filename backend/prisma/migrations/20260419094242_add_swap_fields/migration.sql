-- AlterTable
ALTER TABLE "Transaction" ADD COLUMN     "isSwap" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "receivedAmount" DOUBLE PRECISION,
ADD COLUMN     "swapFromAsset" TEXT,
ADD COLUMN     "swapToAsset" TEXT;
