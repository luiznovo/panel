const bcrypt = require('bcrypt');
const { db } = require('../handlers/db');
const { logAudit } = require('../handlers/auditlog');

/**
 * CORREÇÃO DE SEGURANÇA: Script de migração para hashear API keys existentes
 * Este script deve ser executado uma vez para migrar keys em texto plano para hasheadas
 */

async function migrateApiKeys() {
    console.log('🔄 Iniciando migração de API keys...');
    
    try {
        const apiKeys = await db.get('apiKeys') || [];
        let migratedCount = 0;
        
        for (const key of apiKeys) {
            // Pular keys já hasheadas
            if (key.hashed) {
                continue;
            }
            
            // Hashear a key
            const hashedKey = await bcrypt.hash(key.key, 10);
            
            // Atualizar o objeto
            key.key = hashedKey;
            key.hashed = true;
            key.migratedAt = new Date().toISOString();
            
            migratedCount++;
            
            console.log(`✅ Migrada API key: ${key.name || key.id}`);
        }
        
        // Salvar as keys atualizadas
        if (migratedCount > 0) {
            await db.set('apiKeys', apiKeys);
            
            logAudit('system', 'migration', 'api_keys:migration_completed', 'localhost', {
                migratedCount,
                totalKeys: apiKeys.length
            });
            
            console.log(`✅ Migração concluída! ${migratedCount} API keys foram hasheadas.`);
        } else {
            console.log('ℹ️  Nenhuma API key precisou ser migrada.');
        }
        
    } catch (error) {
        console.error('❌ Erro durante a migração:', error);
        
        logAudit('system', 'migration', 'api_keys:migration_failed', 'localhost', {
            error: error.message
        });
        
        throw error;
    }
}

/**
 * Função para criar uma nova API key hasheada
 */
async function createHashedApiKey(name, userId = null, expiresAt = null) {
    const keyValue = require('crypto').randomBytes(32).toString('hex');
    const hashedKey = await bcrypt.hash(keyValue, 10);
    
    const apiKey = {
        id: require('uuid').v4(),
        name,
        key: hashedKey,
        hashed: true,
        userId,
        expiresAt,
        status: 'active',
        createdAt: new Date().toISOString(),
        lastUsed: null,
        usageCount: 0
    };
    
    const apiKeys = await db.get('apiKeys') || [];
    apiKeys.push(apiKey);
    await db.set('apiKeys', apiKeys);
    
    logAudit(userId || 'system', name, 'api_key:created', 'localhost', {
        keyId: apiKey.id,
        expiresAt
    });
    
    // Retornar a key em texto plano apenas uma vez
    return {
        ...apiKey,
        plainKey: keyValue // Apenas para mostrar ao usuário uma vez
    };
}

/**
 * Função para desabilitar uma API key
 */
async function disableApiKey(keyId, userId = 'system') {
    const apiKeys = await db.get('apiKeys') || [];
    const keyIndex = apiKeys.findIndex(k => k.id === keyId);
    
    if (keyIndex === -1) {
        throw new Error('API key não encontrada');
    }
    
    apiKeys[keyIndex].status = 'disabled';
    apiKeys[keyIndex].disabledAt = new Date().toISOString();
    
    await db.set('apiKeys', apiKeys);
    
    logAudit(userId, 'admin', 'api_key:disabled', 'localhost', {
        keyId,
        keyName: apiKeys[keyIndex].name
    });
    
    return apiKeys[keyIndex];
}

/**
 * Função para listar API keys (sem mostrar as keys hasheadas)
 */
async function listApiKeys() {
    const apiKeys = await db.get('apiKeys') || [];
    
    return apiKeys.map(key => ({
        id: key.id,
        name: key.name,
        userId: key.userId,
        status: key.status,
        hashed: key.hashed,
        createdAt: key.createdAt,
        lastUsed: key.lastUsed,
        usageCount: key.usageCount,
        expiresAt: key.expiresAt
    }));
}

module.exports = {
    migrateApiKeys,
    createHashedApiKey,
    disableApiKey,
    listApiKeys
};

// Executar migração se chamado diretamente
if (require.main === module) {
    migrateApiKeys()
        .then(() => {
            console.log('🎉 Migração concluída com sucesso!');
            process.exit(0);
        })
        .catch((error) => {
            console.error('💥 Falha na migração:', error);
            process.exit(1);
        });
}