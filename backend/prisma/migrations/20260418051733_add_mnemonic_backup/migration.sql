-- AlterTable
ALTER TABLE "User" ADD COLUMN     "encryptedMnemonic" TEXT,
ADD COLUMN     "isBackedUp" BOOLEAN NOT NULL DEFAULT false;
