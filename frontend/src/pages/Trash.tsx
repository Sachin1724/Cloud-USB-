import React from 'react';

const Trash: React.FC = () => {
    return (
        <div className="flex-1 flex flex-col h-full bg-dn-bg overflow-hidden">
            <header className="h-16 px-8 flex items-center border-b border-dn-border/10 bg-dn-bg/80 backdrop-blur-md">
                <span className="text-[10px] font-black uppercase tracking-widest text-dn-error">Vault Security</span>
            </header>

            <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
                <div className="w-24 h-24 rounded-[40px] bg-dn-error/5 flex items-center justify-center mb-8 border border-dn-error/10">
                    <span className="material-symbols-outlined text-dn-error text-5xl">delete_sweep</span>
                </div>
                
                <h2 className="text-3xl font-black text-dn-text mb-4">Native Recycle Bin Active</h2>
                <p className="text-dn-subtext text-sm max-w-md leading-relaxed">
                    Deletions from the web are now synced directly with your Windows Recycle Bin. 
                    To recover a file, please check the Recycle Bin on your host computer.
                </p>

                <div className="mt-12 grid grid-cols-1 md:grid-cols-2 gap-4 max-w-2xl w-full">
                    <div className="p-6 bg-dn-surface-low rounded-3xl border border-dn-border/5 text-left">
                        <span className="material-symbols-outlined text-dn-primary mb-3">shield</span>
                        <h4 className="text-sm font-bold text-dn-text mb-1">Double Protection</h4>
                        <p className="text-[11px] text-dn-subtext">Files are moved locally, not permanently deleted, ensuring you never lose data by accident.</p>
                    </div>
                    <div className="p-6 bg-dn-surface-low rounded-3xl border border-dn-border/5 text-left">
                        <span className="material-symbols-outlined text-dn-primary mb-3">sync</span>
                        <h4 className="text-sm font-bold text-dn-text mb-1">Local Control</h4>
                        <p className="text-[11px] text-dn-subtext">Empty the Recycle Bin on your PC to permanently free up space on your drives.</p>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Trash;
