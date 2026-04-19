// src/services/emailService.js
import { Resend } from 'resend';
import dotenv from 'dotenv';
dotenv.config();

const resend = new Resend(process.env.RESEND_API_KEY);

// Use custom domain from environment, fallback to Resend's test domain
const FROM = process.env.FROM_EMAIL
  ? `${process.env.FROM_NAME || 'DayFi'} <${process.env.FROM_EMAIL}>`
  : 'DayFi <onboarding@resend.dev>';

export async function sendOTP(email, otp, isNewUser = false) {
  const subject = isNewUser
    ? `${otp} is your DayFi verification code`
    : `${otp} — Sign in to DayFi`;

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>DayFi Verification</title>
</head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f5f5f5;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f5;padding:40px 0;">
    <tr>
      <td align="center">
        <table width="480" cellpadding="0" cellspacing="0" style="background:#000;border-radius:16px;overflow:hidden;">
          <tr>
            <td style="padding:40px 40px 20px;text-align:center;">
              <h1 style="color:#fff;font-size:28px;font-weight:700;letter-spacing:-1px;margin:0;">dayfi.</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:0 40px 40px;">
              <p style="color:#888;font-size:14px;margin-bottom:8px;">
                ${isNewUser ? 'Create your wallet' : 'Sign in to your wallet'}
              </p>
              <h2 style="color:#fff;font-size:22px;font-weight:600;margin-bottom:24px;">
                ${isNewUser ? 'Welcome to DayFi' : 'Your sign-in code'}
              </h2>
              <div style="background:#111;border:1px solid #222;border-radius:12px;padding:28px;text-align:center;margin-bottom:24px;">
                <p style="color:#666;font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:12px;">
                  Verification Code
                </p>
                <p style="color:#fff;font-size:42px;font-weight:700;letter-spacing:12px;margin:0;">
                  ${otp}
                </p>
                <p style="color:#555;font-size:12px;margin-top:12px;">
                  Expires in 10 minutes
                </p>
              </div>
              <p style="color:#666;font-size:13px;line-height:1.6;">
                ${isNewUser
                  ? 'Enter this code in the DayFi app to create your USDC wallet.'
                  : 'Enter this code to access your DayFi wallet. Never share this code with anyone.'
                }
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 40px;border-top:1px solid #111;">
              <p style="color:#444;font-size:11px;text-align:center;margin:0;">
                If you didn't request this, please ignore this email.<br>
                © ${new Date().getFullYear()} DayFi — Send money with just a username.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const { error } = await resend.emails.send({
    from: FROM,
    to: email,
    subject,
    html,
    text: `Your DayFi verification code is: ${otp}\n\nExpires in 10 minutes. Never share this code.`,
  });

  if (error) throw new Error(error.message);

  console.log(`📧 OTP sent to ${email}`);
}

export async function sendWelcomeEmail(email, username) {
  const html = `
<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,sans-serif;background:#f5f5f5;padding:40px 0;margin:0;">
  <table width="480" cellpadding="0" cellspacing="0" style="background:#000;border-radius:16px;margin:0 auto;">
    <tr>
      <td style="padding:40px;text-align:center;">
        <h1 style="color:#fff;font-size:28px;margin-bottom:8px;">dayfi.</h1>
        <p style="color:#888;font-size:14px;margin-bottom:32px;">Your wallet is ready</p>
        <div style="background:#111;border:1px solid #222;border-radius:12px;padding:24px;margin-bottom:24px;">
          <p style="color:#666;font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">Your DayFi Username</p>
          <p style="color:#fff;font-size:24px;font-weight:700;margin:0;">@${username}</p>
          <p style="color:#555;font-size:12px;margin-top:4px;">${username}@dayfi.me</p>
        </div>
        <p style="color:#666;font-size:13px;line-height:1.6;">
          Anyone can now send you USDC using just your username.
          Your funds are secured on the Stellar network.
        </p>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const { error } = await resend.emails.send({
    from: FROM,
    to: email,
    subject: `Welcome to DayFi, @${username}!`,
    html,
  });

  if (error) throw new Error(error.message);
}

// ─── Transaction Emails ────────────────────────────────────────────────────────

export async function sendPaymentReceivedEmail(email, senderUsername, amount, asset, memo = null) {
  const html = `
<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,sans-serif;background:#f5f5f5;padding:40px 0;margin:0;">
  <table width="480" cellpadding="0" cellspacing="0" style="background:#000;border-radius:16px;margin:0 auto;">
    <tr>
      <td style="padding:40px;text-align:center;">
        <h1 style="color:#fff;font-size:28px;margin-bottom:8px;">dayfi.</h1>
        <p style="color:#888;font-size:14px;margin-bottom:32px;">You received a payment</p>
        
        <div style="background:#111;border:1px solid #222;border-radius:12px;padding:24px;margin-bottom:24px;">
          <p style="color:#666;font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">From</p>
          <p style="color:#fff;font-size:20px;font-weight:700;margin:0;">@${senderUsername}</p>
        </div>

        <div style="background:#1a1a1a;border:2px solid #27ae60;border-radius:12px;padding:24px;margin-bottom:24px;">
          <p style="color:#27ae60;font-size:14px;margin-bottom:8px;">✅ Amount Received</p>
          <p style="color:#fff;font-size:32px;font-weight:700;margin:0;">+${amount} ${asset}</p>
        </div>

        ${memo ? `<p style="color:#888;font-size:13px;padding:16px;background:#111;border-radius:8px;margin-bottom:24px;">📝 ${memo}</p>` : ''}

        <p style="color:#666;font-size:13px;line-height:1.6;">
          Your payment is confirmed and available in your DayFi wallet.
        </p>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const { error } = await resend.emails.send({
    from: FROM,
    to: email,
    subject: `You received ${amount} ${asset} from @${senderUsername}`,
    html,
  });

  if (error) throw new Error(error.message);
  console.log(`📧 Payment received email sent to ${email}`);
}

export async function sendPaymentSentEmail(email, recipientUsername, amount, asset, memo = null) {
  const html = `
<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,sans-serif;background:#f5f5f5;padding:40px 0;margin:0;">
  <table width="480" cellpadding="0" cellspacing="0" style="background:#000;border-radius:16px;margin:0 auto;">
    <tr>
      <td style="padding:40px;text-align:center;">
        <h1 style="color:#fff;font-size:28px;margin-bottom:8px;">dayfi.</h1>
        <p style="color:#888;font-size:14px;margin-bottom:32px;">Payment sent</p>
        
        <div style="background:#111;border:1px solid #222;border-radius:12px;padding:24px;margin-bottom:24px;">
          <p style="color:#666;font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">To</p>
          <p style="color:#fff;font-size:20px;font-weight:700;margin:0;">@${recipientUsername}</p>
        </div>

        <div style="background:#1a1a1a;border:2px solid #e74c3c;border-radius:12px;padding:24px;margin-bottom:24px;">
          <p style="color:#e74c3c;font-size:14px;margin-bottom:8px;">✓ Amount Sent</p>
          <p style="color:#fff;font-size:32px;font-weight:700;margin:0;">−${amount} ${asset}</p>
        </div>

        ${memo ? `<p style="color:#888;font-size:13px;padding:16px;background:#111;border-radius:8px;margin-bottom:24px;">📝 ${memo}</p>` : ''}

        <p style="color:#666;font-size:13px;line-height:1.6;">
          Your payment has been confirmed on the Stellar network.
        </p>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const { error } = await resend.emails.send({
    from: FROM,
    to: email,
    subject: `Payment sent to @${recipientUsername}`,
    html,
  });

  if (error) throw new Error(error.message);
  console.log(`📧 Payment sent email sent to ${email}`);
}

export async function sendSwapCompleteEmail(email, fromAsset, toAsset, sentAmount, receivedAmount) {
  const html = `
<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,sans-serif;background:#f5f5f5;padding:40px 0;margin:0;">
  <table width="480" cellpadding="0" cellspacing="0" style="background:#000;border-radius:16px;margin:0 auto;">
    <tr>
      <td style="padding:40px;text-align:center;">
        <h1 style="color:#fff;font-size:28px;margin-bottom:8px;">dayfi.</h1>
        <p style="color:#888;font-size:14px;margin-bottom:32px;">Swap completed</p>
        
        <div style="background:#111;border:1px solid #222;border-radius:12px;padding:24px;margin-bottom:24px;">
          <p style="color:#666;font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:16px;">You Swapped</p>
          <p style="color:#e74c3c;font-size:20px;font-weight:700;margin:0;">−${sentAmount} ${fromAsset}</p>
        </div>

        <div style="text-align:center;margin:16px 0;">
          <p style="color:#666;font-size:12px;">→</p>
        </div>

        <div style="background:#1a1a1a;border:2px solid #27ae60;border-radius:12px;padding:24px;margin-bottom:24px;">
          <p style="color:#27ae60;font-size:12px;letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">You Received</p>
          <p style="color:#fff;font-size:20px;font-weight:700;margin:0;">+${receivedAmount} ${toAsset}</p>
        </div>

        <p style="color:#666;font-size:13px;line-height:1.6;">
          Your swap on the Stellar DEX has been confirmed.
        </p>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const { error } = await resend.emails.send({
    from: FROM,
    to: email,
    subject: `Swap complete: ${sentAmount} ${fromAsset} → ${receivedAmount} ${toAsset}`,
    html,
  });

  if (error) throw new Error(error.message);
  console.log(`📧 Swap complete email sent to ${email}`);
}