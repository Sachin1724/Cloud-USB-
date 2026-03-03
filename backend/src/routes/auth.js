import express from 'express';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import fetch from 'node-fetch'; // assuming node 16+ or node-fetch installed

const router = express.Router();

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const client = new OAuth2Client(GOOGLE_CLIENT_ID);
const JWT_SECRET = process.env.JWT_SECRET || '';

function requireJwtSecret(res) {
    if (!JWT_SECRET) {
        res.status(500).json({ error: 'Server auth misconfigured: JWT secret missing' });
        return false;
    }
    return true;
}

router.post('/login', async (req, res) => {
    const { google_token } = req.body;
    if (!requireJwtSecret(res)) return;

    if (google_token) {
        try {
            let email, sub;

            // Method A: Check if it's an ID Token with strict audience match.
            try {
                const ticket = await client.verifyIdToken({
                    idToken: google_token,
                    audience: GOOGLE_CLIENT_ID,
                });
                const payload = ticket.getPayload();
                if (payload && payload.email) {
                    email = payload.email;
                    sub = payload.sub;
                    console.log("[Auth] Google ID Token verified for:", email);
                }
            } catch (idTokenError) {
                console.error("Method A (ID Token) Failed:", idTokenError.message);

                // Method B: Fallback to access token introspection.
                try {
                    const response = await fetch(`https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=${google_token}`);
                    const data = await response.json();
                    const audience = data.aud || data.azp;
                    const audienceValid = GOOGLE_CLIENT_ID && audience === GOOGLE_CLIENT_ID;
                    if (!data.error && data.email && audienceValid) {
                        email = data.email;
                        sub = data.sub;
                    } else {
                        console.error("Method B (Access Token) Failed:", data.error || data.error_description || 'invalid audience');
                    }
                } catch (accessErr) {
                    console.error("Method B (Access Token) Fetch Error:", accessErr.message);
                }
            }

            if (!email) {
                console.error("Token verification completely failed for user.");
                return res.status(401).json({ error: 'Invalid Google Token (Neither ID nor Access Token)' });
            }

            // SECURITY ENFORCEMENT: Check Allowed Users
            const allowedEmailsStr = process.env.ALLOWED_EMAILS || '';
            const allowedEmails = allowedEmailsStr.split(',').map(e => e.trim().toLowerCase()).filter(e => e.length > 0);

            if (allowedEmails.length > 0 && !allowedEmails.includes(email.toLowerCase())) {
                console.error(`[SECURITY TRAP] Unauthorized Account Entry Attempt: ${email}`);
                return res.status(403).json({ error: 'Access Denied: Unregistered External Account' });
            }

            // Issue our own JWT for the rest of the app based on their Google email
            const token = jwt.sign({ user: email, g_uid: sub || email }, JWT_SECRET, { expiresIn: '24h' });
            return res.json({ token, user: email });

        } catch (error) {
            console.error('Google Auth Error:', error);
            return res.status(401).json({ error: 'Failed to authenticate with Google' });
        }
    }

    return res.status(401).json({ error: 'ACCESS DENIED. Invalid security clearance.' });
});

export const authenticateToken = (req, res, next) => {
    if (!JWT_SECRET) return res.status(500).json({ error: 'Server auth misconfigured: JWT secret missing' });
    const authHeader = req.headers['authorization'];
    const token = (authHeader && authHeader.split(' ')[1]) || req.query.token;

    if (!token) return res.status(401).json({ error: 'Token missing' });

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) return res.status(403).json({ error: 'Invalid token' });

        // Constrain scoped share tokens to a single safe operation/path.
        if (user?.scope === 'share') {
            const isDownload = req.path === '/download';
            const requestedPath = typeof req.query.path === 'string' ? req.query.path : '';
            const requestedDrive = typeof req.query.drive === 'string' ? req.query.drive : '';

            if (!isDownload) return res.status(403).json({ error: 'Scoped token can only download files' });
            if (!user.path || requestedPath !== user.path) return res.status(403).json({ error: 'Scoped token path mismatch' });
            if ((user.drive || '') !== requestedDrive) return res.status(403).json({ error: 'Scoped token drive mismatch' });
        }

        req.user = user;
        next();
    });
};

export default router;
