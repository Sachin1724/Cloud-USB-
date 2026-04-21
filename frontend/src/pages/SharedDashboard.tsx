import React, { useState, useEffect } from 'react';
import axios from 'axios';

interface SharedLink {
    token: string;
    path: string;
    drive: string;
    views: number;
    createdAt: string;
}

const SharedDashboard: React.FC = () => {
    const RAW_API = (import.meta as any).env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;
    
    const [links, setLinks] = useState<SharedLink[]>([]);
    const [loading, setLoading] = useState(true);

    const fetchLinks = async () => {
        setLoading(true);
        try {
            const token = localStorage.getItem('drivenet_token');
            const res = await axios.get(`${API}/api/fs/share/links`, {
                headers: { Authorization: `Bearer ${token}` }
            });
            setLinks(res.data.items || []);
        } catch (err) {
            console.error('Fetch shared links error:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchLinks();
    }, []);

    const copyToClipboard = (text: string) => {
        navigator.clipboard.writeText(text);
        alert('Link copied to clipboard!');
    };

    return (
        <div className="flex-1 flex flex-col h-full bg-dn-bg overflow-hidden">
            <header className="h-16 px-8 flex items-center border-b border-dn-border/10 bg-dn-bg/80 backdrop-blur-md">
                <span className="text-[10px] font-black uppercase tracking-widest text-dn-accent">Share Hub</span>
            </header>

            <div className="flex-1 overflow-y-auto p-8 custom-scrollbar">
                <div className="mb-8 flex justify-between items-end">
                    <div>
                        <h2 className="text-2xl font-black text-dn-text">Shared Links</h2>
                        <p className="text-dn-subtext text-xs mt-1">Manage public access and track viewer activity</p>
                    </div>
                    <div className="px-4 py-2 bg-dn-accent/10 border border-dn-accent/20 rounded-xl">
                        <span className="text-[10px] font-black uppercase tracking-widest text-dn-accent">
                            {links.length} Active Links
                        </span>
                    </div>
                </div>

                {loading ? (
                    <div className="flex flex-col items-center justify-center py-32 gap-4">
                        <div className="w-8 h-8 border-2 border-dn-accent/20 border-t-dn-accent rounded-full animate-spin" />
                    </div>
                ) : links.length === 0 ? (
                    <div className="py-32 text-center opacity-30">
                        <span className="material-symbols-outlined text-6xl mb-4">share</span>
                        <p className="text-xs font-bold uppercase tracking-widest">No active share links</p>
                    </div>
                ) : (
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                        {links.map((link, idx) => (
                            <div 
                                key={idx}
                                className="group p-6 bg-dn-surface-low rounded-3xl border border-dn-border/5 hover:border-dn-accent/30 transition-all flex flex-col gap-4"
                            >
                                <div className="flex items-start justify-between">
                                    <div className="flex items-center gap-3">
                                        <div className="w-10 h-10 rounded-2xl bg-dn-accent/10 flex items-center justify-center text-dn-accent">
                                            <span className="material-symbols-outlined">link</span>
                                        </div>
                                        <div className="flex flex-col">
                                            <span className="text-sm font-bold text-dn-text truncate max-w-[200px]">{link.path.split('/').pop()}</span>
                                            <span className="text-[10px] text-dn-subtext font-bold uppercase tracking-tighter opacity-60">{link.drive}</span>
                                        </div>
                                    </div>
                                    <div className="flex flex-col items-end">
                                        <span className="text-xl font-black text-dn-text">{link.views}</span>
                                        <span className="text-[8px] font-black uppercase tracking-widest text-dn-muted">Views</span>
                                    </div>
                                </div>

                                <div className="h-px bg-dn-border/5 w-full" />

                                <div className="flex items-center justify-between gap-2">
                                    <div className="flex flex-col">
                                        <span className="text-[8px] font-black uppercase tracking-widest text-dn-muted mb-1">Created</span>
                                        <span className="text-[10px] font-bold text-dn-subtext">{new Date(link.createdAt).toLocaleDateString()}</span>
                                    </div>
                                    <div className="flex gap-2">
                                        <button 
                                            onClick={() => copyToClipboard(`${window.location.origin}/s/${link.token}`)}
                                            className="px-4 py-2 bg-dn-surface-highest hover:bg-dn-accent/20 hover:text-dn-accent rounded-xl text-[10px] font-black uppercase tracking-widest transition-all"
                                        >
                                            Copy View Link
                                        </button>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </div>
    );
};

export default SharedDashboard;
