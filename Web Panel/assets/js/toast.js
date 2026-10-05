/**
 * Toast 通知管理器
 * 提供全局消息通知功能
 */
class ToastManager {
    constructor() {
        this.container = document.createElement('div');
        this.container.className = 'toast-container';
        document.body.appendChild(this.container);
    }
    
    show(message, type = 'info', duration = 3000) {
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        
        const icon = document.createElement('i');
        icon.className = `fas fa-${this.getIcon(type)}`;
        
        const messageSpan = document.createElement('span');
        messageSpan.className = 'toast-message';
        messageSpan.textContent = message;
        
        toast.appendChild(icon);
        toast.appendChild(messageSpan);
        this.container.appendChild(toast);
        
        // 触发显示动画
        requestAnimationFrame(() => {
            toast.classList.add('show');
        });
        
        // 自动隐藏
        setTimeout(() => {
            toast.classList.remove('show');
            setTimeout(() => {
                toast.remove();
            }, 300);
        }, duration);
        
        return toast;
    }
    
    success(message, duration) {
        return this.show(message, 'success', duration);
    }
    
    error(message, duration) {
        return this.show(message, 'error', duration);
    }
    
    warning(message, duration) {
        return this.show(message, 'warning', duration);
    }
    
    info(message, duration) {
        return this.show(message, 'info', duration);
    }
    
    getIcon(type) {
        const icons = {
            success: 'check-circle',
            error: 'times-circle',
            warning: 'exclamation-triangle',
            info: 'info-circle'
        };
        return icons[type] || icons.info;
    }
}

// 全局实例
const toast = new ToastManager();
