import React, { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import axios from 'axios';
import { GoogleLogin } from '@react-oauth/google';

const Login: React.FC = () => {
    const RAW_API = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;
    const navigate = useNavigate();
    const [searchParams] = useSearchParams();
    const isAgentMode = searchParams.get('agent') === 'true';
    const [error, setError] = useState('');
    const [agentStatus, setAgentStatus] = useState('');

    useEffect(() => {
        if (isAgentMode) setAgentStatus('Agent Mode — Sign in to activate device sync');
    }, [isAgentMode]);

    const sendTokenToAgent = async (token: string, user: string) => {
        if (!isAgentMode) return;
        try {
            setAgentStatus('Sending token to agent...');
            await fetch('http://localhost:9292/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ token, user }),
            });
            setAgentStatus('✓ Agent authenticated — you can close this window');
        } catch {
            setAgentStatus('✓ Authenticated');
        }
    };

    const handleGoogleSuccess = async (credentialResponse: any) => {
        setError('');
        try {
            const res = await axios.post(`${API}/api/auth/login`, { google_token: credentialResponse.credential });
            if (res.data.token) {
                localStorage.setItem('drivenet_token', res.data.token);
                await sendTokenToAgent(res.data.token, res.data.user);
                if (!isAgentMode) navigate('/dashboard');
            }
        } catch (err: any) {
            setError(err.response?.data?.error || 'Authentication failed. Please try again.');
        }
    };

    return (
        <div className="bg-dn-bg font-sans text-dn-text min-h-screen flex flex-col">
            {/* Background ambient glow */}
            <div className="fixed inset-0 pointer-events-none overflow-hidden">
                <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[800px] rounded-full blur-[120px]"
                    style={{ background: 'radial-gradient(circle, rgba(99,102,241,0.08) 0%, transparent 70%)' }} />
            </div>

            {agentStatus && (
                <div className="relative z-20 text-center py-3 text-xs font-bold uppercase tracking-widest border-b border-dn-accent/20 bg-dn-accent/5 text-dn-primary">
                    {agentStatus}
                </div>
            )}

            <main className="relative z-10 flex-grow flex items-center justify-center p-6">
                <div className="w-full max-w-[400px]">
                    {/* Logo Section */}
                    <div className="flex flex-col items-center mb-12">
                        <div className="w-16 h-16 rounded-2xl flex items-center justify-center mb-6 shadow-dn-glow bg-gradient-to-br from-dn-accent to-dn-accent-container">
                            <span className="material-symbols-outlined text-dn-bg text-3xl font-black">cloud_upload</span>
                        </div>
                        <h1 className="text-3xl font-black tracking-tighter text-dn-text mb-2">Welcome back</h1>
                        <p className="text-dn-subtext text-sm text-center">Enter the vault to access your private network</p>
                    </div>

                    {/* Login Card */}
                    <div className="glass-card rounded-2xl p-10 flex flex-col items-center">
                        {error && (
                            <div className="w-full mb-8 text-xs font-bold uppercase tracking-widest p-4 rounded-xl text-center border border-dn-error/20 bg-dn-error/5 text-dn-error">
                                {error}
                            </div>
                        )}

                        <div className="w-full flex justify-center">
                            <GoogleLogin
                                onSuccess={handleGoogleSuccess}
                                onError={() => setError('Google sign in failed')}
                                theme="filled_black"
                                shape="pill"
                                size="large"
                                text="continue_with"
                                width="320"
                            />
                        </div>

                        <div className="mt-10 pt-8 border-t border-dn-border/10 w-full text-center">
                            <p className="text-[10px] text-dn-muted uppercase tracking-widest font-bold leading-relaxed opacity-60">
                                Protected by AES-256 military encryption
                            </p>
                        </div>
                    </div>

                    <div className="text-center mt-8">
                        <button onClick={() => navigate('/')}
                            className="text-xs font-bold uppercase tracking-widest text-dn-muted hover:text-dn-primary transition-colors flex items-center justify-center gap-2 mx-auto">
                            <span className="material-symbols-outlined text-sm">arrow_back</span>
                            Back to home
                        </button>
                    </div>
                </div>
            </main>
        </div>
    );
};

export default Login;
