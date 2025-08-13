const { db } = require('./db');
const fs = require('fs');
const path = require('path');

/**
 * CORREÇÃO DE SEGURANÇA: Sistema de logs de auditoria melhorado
 */

function AdminAudit(userId, username, action, ip, metadata = {}) {
    this.userId = userId;
    this.username = username;
    this.action = action;
    this.ip = ip;
    this.metadata = metadata;
    this.timestamp = new Date().toISOString();
    this.severity = getSeverity(action);
}

function getSeverity(action) {
    const criticalActions = [
        'admin:access_denied',
        'login:failed', 
        'plan:change_blocked',
        'error:occurred',
        'validation:failed',
        'unauthorized_access'
    ];
    
    const warningActions = [
        'admin:access_granted',
        'plan:change_attempt',
        'instance:delete',
        'user:delete',
        'config:change'
    ];
    
    if (criticalActions.some(critical => action.includes(critical))) {
        return 'critical';
    }
    
    if (warningActions.some(warning => action.includes(warning))) {
        return 'warning';
    }
    
    return 'info';
}

function ensureLogDirectory() {
    const logDir = path.join(__dirname, '../storage/logs');
    if (!fs.existsSync(logDir)) {
        fs.mkdirSync(logDir, { recursive: true });
    }
    return logDir;
}

function saveToFile(auditEntry) {
    try {
        const logDir = ensureLogDirectory();
        const date = new Date().toISOString().split('T')[0];
        const logFile = path.join(logDir, `audit-${date}.log`);
        const logLine = JSON.stringify(auditEntry) + '\n';
        
        fs.appendFileSync(logFile, logLine);
    } catch (error) {
        console.error('Erro ao salvar log de auditoria em arquivo:', error);
    }
}

function sendAlert(auditEntry) {
    if (auditEntry.severity === 'critical') {
        console.warn('🚨 ALERTA DE SEGURANÇA:', {
            action: auditEntry.action,
            user: auditEntry.username,
            ip: auditEntry.ip,
            timestamp: auditEntry.timestamp,
            metadata: auditEntry.metadata
        });
    }
}

async function logAudit(userId, username, action, ip, metadata = {}) {
    const newAudit = new AdminAudit(userId, username, action, ip, metadata);
    let audits = [];

    try {
        const data = await db.get('audits');
        audits = data ? JSON.parse(data) : [];
    } catch (err) {
        console.error('Error fetching audits:', err);
    }

    audits.push(newAudit);

    // Manter apenas os últimos 1000 logs em memória
    if (audits.length > 1000) {
        audits = audits.slice(-1000);
    }

    try {
        await db.set('audits', JSON.stringify(audits));
        
        // CORREÇÃO DE SEGURANÇA: Salvar também em arquivo
        saveToFile(newAudit);
        
        // CORREÇÃO DE SEGURANÇA: Alertas para ações críticas
        sendAlert(newAudit);
        
    } catch (err) {
        console.error('Error saving audits:', err);
    }
}

// CORREÇÃO DE SEGURANÇA: Função para buscar logs com filtros
async function getAuditLogs(filters = {}) {
    try {
        const data = await db.get('audits');
        let audits = data ? JSON.parse(data) : [];
        
        if (filters.userId) {
            audits = audits.filter(audit => audit.userId === filters.userId);
        }
        
        if (filters.action) {
            audits = audits.filter(audit => audit.action.includes(filters.action));
        }
        
        if (filters.severity) {
            audits = audits.filter(audit => audit.severity === filters.severity);
        }
        
        if (filters.startDate) {
            audits = audits.filter(audit => audit.timestamp >= filters.startDate);
        }
        
        if (filters.endDate) {
            audits = audits.filter(audit => audit.timestamp <= filters.endDate);
        }
        
        return audits.slice(0, filters.limit || 100);
    } catch (err) {
        console.error('Error fetching audit logs:', err);
        return [];
    }
}

module.exports = { logAudit, getAuditLogs };
