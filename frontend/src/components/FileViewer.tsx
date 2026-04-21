import React from 'react';

interface FileViewerProps {
    file: {
        name: string;
        is_dir: boolean;
        path: string;
        drive: string;
    };
    onClose: () => void;
    token?: string; // Optional token for shared views
}

const FileViewer: React.FC<FileViewerProps> = ({ file, onClose, token }) => {
    const RAW_API = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;
    
    const ext = file.name.split('.').pop()?.toLowerCase();
    const isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].includes(ext!);
    const isVideo = ['mp4', 'webm', 'mov', 'avi', 'mkv'].includes(ext!);
    const isPdf = ext === 'pdf';

    const getSourceUrl = () => {
        const base = isVideo ? `${API}/api/fs/video` : `${API}/api/fs/download`;
        const url = new URL(base);
        url.searchParams.set('path', file.path);
        url.searchParams.set('drive', file.drive);
        if (token) url.searchParams.set('token', token);
        else {
            const authToken = localStorage.getItem('drivenet_token');
            if (authToken) url.searchParams.set('token', authToken); // Fallback for download auth if not using Bearer
        }
        return url.toString();
    };

    // For images/videos we might need the direct URL with the bearer in query or a specialized route
    // The current backend supports ?token= for /download and /video
    const mediaUrl = getSourceUrl();

    return (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-dn-bg/95 backdrop-blur-xl animate-in fade-in duration-300">
            <div className="absolute top-6 right-6 flex items-center gap-4 z-[110]">
                <button 
                    onClick={() => {
                        const link = document.createElement('a');
                        link.href = mediaUrl;
                        link.download = file.name;
                        link.click();
                    }}
                    className="w-10 h-10 rounded-full bg-white/5 hover:bg-dn-accent/20 hover:text-dn-accent flex items-center justify-center text-dn-text transition-all"
                    title="Download"
                >
                    <span className="material-symbols-outlined text-xl">download</span>
                </button>
                <button 
                    onClick={onClose}
                    className="w-10 h-10 rounded-full bg-white/5 hover:bg-dn-error/20 hover:text-dn-error flex items-center justify-center text-dn-text transition-all"
                    title="Close"
                >
                    <span className="material-symbols-outlined text-xl">close</span>
                </button>
            </div>

            <div className="flex flex-col items-center justify-center w-full h-full p-12 lg:p-24">
                <div className="w-full max-w-5xl h-full flex flex-col items-center justify-center">
                    {/* Header Info */}
                    <div className="mb-8 text-center">
                        <h2 className="text-xl font-black text-dn-text mb-1 uppercase tracking-tighter">{file.name}</h2>
                        <p className="text-[10px] font-bold text-dn-accent uppercase tracking-widest">{file.drive} / {file.path.split('/').slice(0, -1).join(' / ')}</p>
                    </div>

                    {/* Preview Content */}
                    <div className="flex-1 w-full bg-dn-surface-lowest rounded-[40px] border border-dn-border/10 overflow-hidden relative shadow-2xl">
                        {isImage ? (
                            <img 
                                src={mediaUrl} 
                                alt={file.name} 
                                className="w-full h-full object-contain p-4" 
                            />
                        ) : isVideo ? (
                            <video 
                                src={mediaUrl} 
                                controls 
                                autoPlay
                                className="w-full h-full"
                            />
                        ) : isPdf ? (
                            <iframe 
                                src={`${mediaUrl}#toolbar=0`} 
                                className="w-full h-full border-none"
                                title={file.name}
                            />
                        ) : (
                            <div className="w-full h-full flex flex-col items-center justify-center bg-dn-surface-low text-dn-muted">
                                <span className="material-symbols-outlined text-8xl mb-6 opacity-20">description</span>
                                <p className="text-sm font-bold uppercase tracking-widest opacity-40">Preview not available for this file type</p>
                                <button 
                                    onClick={() => window.open(mediaUrl)}
                                    className="mt-8 dn-button-primary px-8 py-3"
                                >
                                    Download to View
                                </button>
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </div>
    );
};

export default FileViewer;
