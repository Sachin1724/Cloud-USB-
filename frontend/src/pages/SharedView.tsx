import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import axios from 'axios';
import FileViewer from '../components/FileViewer';

const SharedView: React.FC = () => {
    const { token } = useParams<{ token: string }>();
    const RAW_API = (import.meta as any).env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;

    const [metadata, setMetadata] = useState<any>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');

    useEffect(() => {
        const fetchMetadata = async () => {
            try {
                const res = await axios.get(`${API}/api/fs/share/metadata`, {
                    params: { token }
                });
                setMetadata(res.data);
            } catch (err: any) {
                setError(err.response?.data?.error || 'Link invalid or expired');
            } finally {
                setLoading(false);
            }
        };
        fetchMetadata();
    }, [token]);

    if (loading) {
        return (
            <div className="min-h-screen bg-dn-bg flex flex-col items-center justify-center text-dn-text">
                <div className="w-12 h-12 border-4 border-dn-accent/20 border-t-dn-accent rounded-full animate-spin mb-6" />
                <span className="text-[10px] font-black uppercase tracking-widest text-dn-muted">Unlocking Shared Asset...</span>
            </div>
        );
    }

    if (error) {
        return (
            <div className="min-h-screen bg-dn-bg flex flex-col items-center justify-center p-8 text-center">
                <div className="w-20 h-20 rounded-3xl bg-dn-error/5 flex items-center justify-center mb-8 border border-dn-error/10">
                    <span className="material-symbols-outlined text-dn-error text-4xl">link_off</span>
                </div>
                <h2 className="text-2xl font-black text-dn-text mb-2">Access Denied</h2>
                <p className="text-dn-subtext text-sm max-w-xs">{error}</p>
                <button 
                    onClick={() => window.location.href = '/'}
                    className="mt-12 dn-button-primary px-12 py-3"
                >
                    Return to Explorer
                </button>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-dn-bg overflow-hidden relative">
            {/* Background design */}
            <div className="absolute top-0 left-0 w-full h-[500px] bg-gradient-to-b from-dn-accent/10 to-transparent opacity-50 blur-3xl pointer-events-none" />

            <div className="relative z-10 w-full h-screen">
                <FileViewer 
                    file={{
                        name: metadata.name,
                        is_dir: false,
                        path: metadata.path,
                        drive: metadata.drive
                    }}
                    onClose={() => window.history.back()}
                    token={token}
                />
            </div>
            
            {/* Floating branding for shared views */}
            <div className="fixed bottom-8 left-1/2 -translate-x-1/2 z-[110] px-6 py-3 bg-dn-surface-lowest/80 backdrop-blur-md rounded-full border border-dn-border/10 flex items-center gap-3">
                <span className="text-[10px] font-black uppercase tracking-widest text-dn-muted">Powered by</span>
                <span className="text-sm font-black tracking-tighter text-dn-text">DriveNet Explorer</span>
            </div>
        </div>
    );
};

export default SharedView;
