import React, { useState, useEffect, useMemo } from 'react';
import axios from 'axios';
import { useNavigate, useLocation, useOutletContext } from 'react-router-dom';
import FileViewer from './FileViewer';
import { toast } from 'react-hot-toast'; // Assuming we want some notification

interface FileItem {
  name: string;
  is_dir: boolean;
  size: number;
  modified: string;
  path: string;
  drive?: string;
}

interface DashboardContext {
    agent: { online: boolean; drive: string | null; drives: any[] } | null;
    user: any;
    fetchData: () => Promise<void>;
}

const FileBrowser: React.FC = () => {
    const RAW_API = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;
    const navigate = useNavigate();
    const location = useLocation();
    const { agent, fetchData } = useOutletContext<DashboardContext>();

    const [files, setFiles] = useState<FileItem[]>([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const [searchQuery, setSearchQuery] = useState('');
    const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
    const [previewFile, setPreviewFile] = useState<FileItem | null>(null);
    const [sharingId, setSharingId] = useState<string | null>(null);

    const queryParams = new URLSearchParams(location.search);
    const currentPath = queryParams.get('path') || '';
    const currentDrive = queryParams.get('drive') || '';

    const fetchFiles = async () => {
        if (!currentDrive) {
            setFiles([]);
            setLoading(false);
            return;
        }

        setLoading(true);
        setError('');
        const token = localStorage.getItem('drivenet_token');
        try {
            const res = await axios.get(`${API}/api/fs/list`, {
                headers: { Authorization: `Bearer ${token}` },
                params: { path: currentPath, drive: currentDrive }
            });
            // FIX: Backend returns 'items', not 'files'
            setFiles(res.data.items || []);
        } catch (err: any) {
            console.error('[FileBrowser] Fetch error:', err);
            setError(err.response?.data?.error || 'Vault connection refused');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchFiles();
    }, [currentPath, currentDrive]);

    // Auto-sync: If no drive is in URL, but agent has one, navigate to it
    useEffect(() => {
        if (!currentDrive && agent?.online && agent?.drive) {
            navigate(`?drive=${encodeURIComponent(agent.drive)}`);
        }
    }, [currentDrive, agent?.online, agent?.drive]);

    const filteredFiles = useMemo(() => {
        return files.filter(f => f.name.toLowerCase().includes(searchQuery.toLowerCase()));
    }, [files, searchQuery]);

    const handleNavigate = (item: FileItem) => {
        if (item.is_dir) {
            const newPath = currentPath ? `${currentPath}/${item.name}` : item.name;
            const newDrive = item.drive || currentDrive;
            navigate(`?drive=${encodeURIComponent(newDrive)}&path=${encodeURIComponent(newPath)}`);
        } else {
            setPreviewFile({ ...item, drive: currentDrive });
        }
    };

    const handleShare = async (item: FileItem) => {
        const token = localStorage.getItem('drivenet_token');
        try {
            const res = await axios.get(`${API}/api/fs/share`, {
                headers: { Authorization: `Bearer ${token}` },
                params: { path: currentPath ? `${currentPath}/${item.name}` : item.name, drive: currentDrive }
            });
            navigator.clipboard.writeText(res.data.viewUrl);
            alert('Share link copied to clipboard!');
        } catch (err) {
            alert('Failed to generate share link');
        }
    };

    const breadcrumbs = useMemo(() => {
        const parts = currentPath.split(/[/\\]/).filter(Boolean);
        return [{ name: 'Vault', path: '', drive: currentDrive }, ...parts.map((p, i) => ({
            name: p,
            path: parts.slice(0, i + 1).join('/'),
            drive: currentDrive
        }))];
    }, [currentPath, currentDrive]);

    const getFileIcon = (item: FileItem) => {
        if (item.is_dir) return 'folder';
        const ext = item.name.split('.').pop()?.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'svg', 'webp'].includes(ext!)) return 'image';
        if (['mp4', 'mov', 'avi', 'mkv'].includes(ext!)) return 'video_file';
        if (['pdf', 'doc', 'docx', 'txt'].includes(ext!)) return 'description';
        if (['zip', 'rar', '7z', 'tar'].includes(ext!)) return 'inventory_2';
        return 'insert_drive_file';
    };

    const formatSize = (bytes: number) => {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    };

    return (
        <div className="flex-1 flex flex-col h-full overflow-hidden">
            {/* Header (Consolidated) */}
            <header className="sticky top-0 w-full z-40 bg-dn-bg/80 backdrop-blur-md flex justify-between items-center h-14 px-6 border-b border-dn-border/5">
                <div className="flex items-center gap-4 overflow-hidden">
                    <span className="text-[9px] font-black uppercase tracking-widest text-dn-accent whitespace-nowrap">Cloud Store</span>
                    <div className="h-3 w-px bg-dn-border/20 shrink-0" />
                    <div className="flex items-center gap-1.5 text-[11px] font-bold text-dn-subtext overflow-hidden">
                        {breadcrumbs.map((b, i) => (
                            <React.Fragment key={i}>
                                <button 
                                    onClick={() => navigate(`?drive=${encodeURIComponent(b.drive)}&path=${encodeURIComponent(b.path)}`)}
                                    className={`hover:text-dn-text whitespace-nowrap transition-colors ${i === breadcrumbs.length - 1 ? 'text-dn-text font-black' : 'opacity-60'}`}
                                >
                                    {b.name}
                                </button>
                                {i < breadcrumbs.length - 1 && <span className="material-symbols-outlined text-[12px] opacity-20">chevron_right</span>}
                            </React.Fragment>
                        ))}
                    </div>
                </div>

                <div className="flex items-center gap-4 flex-1 justify-end max-w-lg">
                    <div className="relative w-full hidden md:block">
                        <span className="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-dn-muted text-xs opacity-50">search</span>
                        <input 
                            className="w-full bg-dn-surface-lowest/50 border border-dn-border/5 rounded-full py-1.5 pl-9 pr-4 text-[11px] focus:ring-1 focus:ring-dn-accent/30 transition-all placeholder:text-dn-muted/40 text-dn-text"
                            placeholder="Find items..."
                            type="text"
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                        />
                    </div>
                </div>
            </header>

            {/* Workspace */}
            <div className="flex-1 overflow-y-auto p-8 bg-dn-bg custom-scrollbar">
                {/* Status bar */}
                <div className="flex items-center justify-between mb-8">
                    <div className="flex items-center gap-3">
                        <div className="flex bg-dn-surface-low p-1 rounded-lg border border-dn-border/5">
                            <button 
                                onClick={() => setViewMode('grid')}
                                className={`flex items-center justify-center p-2 rounded-md transition-all ${viewMode === 'grid' ? 'bg-dn-surface-highest text-dn-primary shadow-sm' : 'text-dn-subtext hover:text-dn-text'}`}
                            >
                                <span className="material-symbols-outlined text-[20px]">grid_view</span>
                            </button>
                            <button 
                                onClick={() => setViewMode('list')}
                                className={`flex items-center justify-center p-2 rounded-md transition-all ${viewMode === 'list' ? 'bg-dn-surface-highest text-dn-primary shadow-sm' : 'text-dn-subtext hover:text-dn-text'}`}
                            >
                                <span className="material-symbols-outlined text-[20px]">list</span>
                            </button>
                        </div>
                    </div>

                    <div className="flex items-center gap-4">
                        <div className={`flex items-center gap-2 px-3 py-1.5 rounded-full border transition-colors ${agent?.online ? 'bg-dn-success/5 border-dn-success/20 text-dn-success' : 'bg-dn-error/5 border-dn-error/20 text-dn-error'}`}>
                            <span className={`w-1.5 h-1.5 rounded-full ${agent?.online ? 'bg-dn-success animate-pulse' : 'bg-dn-error'}`} />
                            <span className="text-[9px] font-black uppercase tracking-widest leading-none">
                                {agent?.online ? 'Sync Active' : 'Agent Offline'}
                            </span>
                        </div>
                        {currentDrive && (
                            <div className="px-3 py-1.5 bg-dn-surface-low border border-dn-border/10 rounded-full flex items-center gap-2">
                                <span className="material-symbols-outlined text-xs text-dn-primary">storage</span>
                                <span className="text-[9px] font-black uppercase tracking-widest text-dn-text">{currentDrive}</span>
                            </div>
                        )}
                    </div>
                </div>

                {!currentDrive ? (
                    <div className="flex flex-col items-center justify-center py-32 text-center">
                        <div className="w-20 h-20 rounded-3xl bg-dn-surface-low flex items-center justify-center mb-6 animate-pulse">
                            <span className="material-symbols-outlined text-dn-muted text-4xl">usb</span>
                        </div>
                        <h3 className="text-xl font-black text-dn-text mb-2">No active drive selected</h3>
                        <p className="text-dn-subtext text-sm max-w-xs mx-auto mb-8">
                            Select a drive in your Windows agent to start exploring your private files.
                        </p>
                        <button 
                            onClick={() => fetchData()}
                            className="dn-button-secondary text-[10px] py-3 tracking-widest uppercase"
                        >
                            <span className="material-symbols-outlined text-sm mr-2 align-middle">refresh</span>
                            Sync with Agent
                        </button>
                    </div>
                ) : loading ? (
                    <div className="flex flex-col items-center justify-center py-32 gap-4">
                        <div className="w-10 h-10 border-4 border-dn-accent/20 border-t-dn-accent rounded-full animate-spin" />
                        <span className="text-[10px] font-bold uppercase tracking-widest text-dn-muted">Unlocking Vault...</span>
                    </div>
                ) : error ? (
                    <div className="bg-dn-error/5 border border-dn-error/20 p-12 rounded-3xl text-center max-w-md mx-auto">
                        <span className="material-symbols-outlined text-dn-error text-6xl mb-6">lock_reset</span>
                        <h3 className="text-xl font-bold mb-2">Security Timeout</h3>
                        <p className="text-dn-subtext text-sm mb-8 leading-relaxed">{error}</p>
                        <button onClick={fetchFiles} className="dn-button-primary w-full py-3">Reconnect to Vault</button>
                    </div>
                ) : (
                    <div className={viewMode === 'grid' 
                        ? "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 gap-6"
                        : "flex flex-col gap-2"
                    }>
                        {filteredFiles.map((file, idx) => (
                            <div 
                                key={idx}
                                onClick={() => handleNavigate(file)}
                                className={`group relative bg-dn-surface-low rounded-2xl transition-all duration-300 cursor-pointer overflow-hidden border border-dn-border/5 ${
                                    viewMode === 'grid' 
                                        ? 'p-6 hover:border-dn-accent/30 hover:shadow-dn-glow active:scale-[0.98]' 
                                        : 'p-3 flex items-center justify-between hover:bg-dn-surface-high'
                                }`}
                            >
                                {viewMode === 'grid' ? (
                                    <>
                                        <div className="flex items-start justify-between mb-4">
                                            <div className={`p-3 rounded-xl ${file.is_dir ? 'bg-dn-accent/5' : 'bg-dn-surface-highest'}`}>
                                                <span className={`material-symbols-outlined text-3xl ${file.is_dir ? 'text-dn-accent' : 'text-dn-subtext'}`} style={{ fontVariationSettings: file.is_dir ? "'FILL' 1" : "" }}>
                                                    {getFileIcon(file)}
                                                </span>
                                            </div>
                                            <button 
                                                onClick={(e) => { e.stopPropagation(); handleShare(file); }}
                                                className="text-dn-muted hover:text-dn-accent transition-colors p-1"
                                            >
                                                <span className="material-symbols-outlined text-lg">share</span>
                                            </button>
                                        </div>
                                        <div>
                                            <h3 className="text-dn-text font-bold text-sm mb-1 truncate" title={file.name}>{file.name}</h3>
                                            <p className="text-dn-subtext text-[10px] font-black uppercase tracking-tight flex items-center gap-2 opacity-60">
                                                <span>{file.is_dir ? 'Folder' : formatSize(file.size)}</span>
                                                <span className="w-1 h-1 bg-dn-muted/30 rounded-full" />
                                                <span>{new Date(file.modified).toLocaleDateString()}</span>
                                            </p>
                                        </div>
                                    </>
                                ) : (
                                    <>
                                        <div className="flex items-center gap-4 flex-1 overflow-hidden">
                                            <span className={`material-symbols-outlined ${file.is_dir ? 'text-dn-accent' : 'text-dn-subtext'}`} style={{ fontVariationSettings: file.is_dir ? "'FILL' 1" : "" }}>
                                                {getFileIcon(file)}
                                            </span>
                                            <span className="text-sm font-semibold truncate text-dn-text">{file.name}</span>
                                        </div>
                                        <div className="flex items-center gap-6 text-[10px] font-black uppercase tracking-tight text-dn-subtext opacity-60">
                                            <span className="w-20 text-right">{file.is_dir ? '--' : formatSize(file.size)}</span>
                                            <span className="w-24 text-right">{new Date(file.modified).toLocaleDateString()}</span>
                                        </div>
                                    </>
                                )}
                            </div>
                        ))}
                        
                        {filteredFiles.length === 0 && (
                            <div className="col-span-full py-32 flex flex-col items-center justify-center opacity-30 text-center">
                                <span className="material-symbols-outlined text-8xl mb-6">folder_off</span>
                                <p className="text-sm font-black uppercase tracking-widest text-dn-subtext">No files found in the vault</p>
                            </div>
                        )}
                    </div>
                )}
            </div>

            {/* File Preview */}
            {previewFile && (
                <FileViewer 
                    file={{
                        ...previewFile,
                        drive: currentDrive,
                        path: currentPath ? `${currentPath}/${previewFile.name}` : previewFile.name
                    }}
                    onClose={() => setPreviewFile(null)}
                />
            )}
        </div>
    );
};

export default FileBrowser;
