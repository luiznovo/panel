const { logAudit } = require('../handlers/auditlog');
const { db } = require('../handlers/db');

/**
 * CORREÇÃO DE SEGURANÇA: Middleware centralizado de segurança
 * Centraliza todas as verificações de autorização e logs de auditoria
 */

/**
 * Middleware de autenticação melhorado
 */
function isAuthenticated(req, res, next) {
    if (!req.user) {
        // Log tentativa de acesso não autorizado
        logAudit('anonymous', 'anonymous', 'access:unauthorized', req.ip, {
            path: req.path,
            method: req.method,
            userAgent: req.headers['user-agent']
        });
        
        if (req.xhr || req.headers.accept?.includes('application/json')) {
            return res.status(401).json({ 
                success: false, 
                message: 'Autenticação necessária' 
            });
        }
        return res.redirect('/auth/login');
    }
    next();
}

/**
 * Middleware de verificação de administrador melhorado
 */
function isAdmin(req, res, next) {
    if (!req.user) {
        logAudit('anonymous', 'anonymous', 'admin:access_denied', req.ip, {
            path: req.path,
            reason: 'not_authenticated'
        });
        
        if (req.xhr || req.headers.accept?.includes('application/json')) {
            return res.status(401).json({ 
                success: false, 
                message: 'Autenticação necessária' 
            });
        }
        return res.redirect('/auth/login');
    }
    
    if (!req.user.admin) {
        logAudit(req.user.userId, req.user.username, 'admin:access_denied', req.ip, {
            path: req.path,
            reason: 'insufficient_privileges'
        });
        
        if (req.xhr || req.headers.accept?.includes('application/json')) {
            return res.status(403).json({ 
                success: false, 
                message: 'Privilégios de administrador necessários' 
            });
        }
        return res.redirect('/');
    }
    
    // Log acesso administrativo
    logAudit(req.user.userId, req.user.username, 'admin:access_granted', req.ip, {
        path: req.path
    });
    
    next();
}

/**
 * Middleware para verificar se usuário pode acessar recurso específico
 */
function isAdminOrSelf(req, res, next) {
    if (!req.user) {
        return res.status(401).json({ 
            success: false, 
            message: 'Autenticação necessária' 
        });
    }
    
    const targetUserId = req.params.userId || req.body.userId || req.body.user;
    
    // Admin pode acessar qualquer recurso
    if (req.user.admin) {
        logAudit(req.user.userId, req.user.username, 'admin:resource_access', req.ip, {
            targetUserId,
            path: req.path
        });
        return next();
    }
    
    // Usuário só pode acessar seus próprios recursos
    if (req.user.userId === targetUserId) {
        return next();
    }
    
    logAudit(req.user.userId, req.user.username, 'access:denied', req.ip, {
        targetUserId,
        path: req.path,
        reason: 'not_owner'
    });
    
    return res.status(403).json({ 
        success: false, 
        message: 'Acesso negado' 
    });
}

/**
 * Middleware para sanitizar respostas de erro
 */
function sanitizeError(err, req, res, next) {
    // Log erro completo para auditoria
    logAudit(
        req.user?.userId || 'anonymous', 
        req.user?.username || 'anonymous', 
        'error:occurred', 
        req.ip, 
        {
            error: err.message,
            stack: err.stack,
            path: req.path,
            method: req.method
        }
    );
    
    // Resposta sanitizada para o usuário
    const sanitizedError = {
        success: false,
        message: 'Erro interno do servidor'
    };
    
    // Em desenvolvimento, mostrar mais detalhes
    if (process.env.NODE_ENV === 'development') {
        sanitizedError.details = err.message;
    }
    
    res.status(err.status || 500).json(sanitizedError);
}

/**
 * Middleware para validar entrada de dados
 */
function validateInput(schema) {
    return (req, res, next) => {
        const { error } = schema.validate(req.body);
        if (error) {
            logAudit(
                req.user?.userId || 'anonymous',
                req.user?.username || 'anonymous',
                'validation:failed',
                req.ip,
                {
                    path: req.path,
                    errors: error.details.map(d => d.message)
                }
            );
            
            return res.status(400).json({
                success: false,
                message: 'Dados inválidos',
                errors: error.details.map(d => d.message)
            });
        }
        next();
    };
}

/**
 * Middleware para log de ações sensíveis
 */
function logSensitiveAction(action) {
    return (req, res, next) => {
        // Log antes da ação
        logAudit(
            req.user?.userId || 'anonymous',
            req.user?.username || 'anonymous',
            `${action}:attempt`,
            req.ip,
            {
                path: req.path,
                method: req.method,
                body: req.body
            }
        );
        
        // Interceptar resposta para log de sucesso/falha
        const originalSend = res.send;
        res.send = function(data) {
            const isSuccess = res.statusCode >= 200 && res.statusCode < 300;
            
            logAudit(
                req.user?.userId || 'anonymous',
                req.user?.username || 'anonymous',
                `${action}:${isSuccess ? 'success' : 'failed'}`,
                req.ip,
                {
                    statusCode: res.statusCode,
                    path: req.path
                }
            );
            
            originalSend.call(this, data);
        };
        
        next();
    };
}

module.exports = {
    isAuthenticated,
    isAdmin,
    isAdminOrSelf,
    sanitizeError,
    validateInput,
    logSensitiveAction
};