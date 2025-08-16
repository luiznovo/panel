#!/usr/bin/env node

/**
 * Script para substituir better-sqlite3 por sqlite3 nativo
 * Resolve problemas de compatibilidade com diferentes versões de GLIBC
 */

const fs = require('fs');
const path = require('path');

console.log('🔧 Iniciando correção do SQLite...');

// Backup do package.json original
const packagePath = path.join(__dirname, 'package.json');
const backupPath = path.join(__dirname, 'package.json.backup');

if (!fs.existsSync(backupPath)) {
    fs.copyFileSync(packagePath, backupPath);
    console.log('✅ Backup do package.json criado');
}

// Ler package.json
const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'));

// Substituir better-sqlite3 por sqlite3
if (packageJson.dependencies['better-sqlite3']) {
    delete packageJson.dependencies['better-sqlite3'];
    packageJson.dependencies['sqlite3'] = '^5.1.6';
    console.log('✅ better-sqlite3 substituído por sqlite3');
}

// Remover better-sqlite3-session-store
if (packageJson.dependencies['better-sqlite3-session-store']) {
    delete packageJson.dependencies['better-sqlite3-session-store'];
    packageJson.dependencies['connect-sqlite3'] = '^0.9.13';
    console.log('✅ better-sqlite3-session-store substituído por connect-sqlite3');
}

// Salvar package.json modificado
fs.writeFileSync(packagePath, JSON.stringify(packageJson, null, 2));
console.log('✅ package.json atualizado');

// Criar arquivo de migração para o código
const migrationCode = `
// Migração de better-sqlite3 para sqlite3
// Substitua as importações no seu código:

// ANTES:
// const sqlite = require('better-sqlite3');
// const SqliteStore = require('better-sqlite3-session-store')(session);
// const sessionStorage = new sqlite('sessions.db');

// DEPOIS:
const sqlite3 = require('sqlite3').verbose();
const SQLiteStore = require('connect-sqlite3')(session);

// Para sessões:
const sessionStore = new SQLiteStore({
    db: 'sessions.db',
    dir: './'
});

// Para banco de dados:
const db = new sqlite3.Database('database.db');

// Exemplo de uso:
// db.serialize(() => {
//     db.run("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)");
//     db.run("INSERT INTO users (name) VALUES (?)", ["admin"]);
//     db.each("SELECT id, name FROM users", (err, row) => {
//         console.log(row.id + ": " + row.name);
//     });
// });
// 
// db.close();
`;

fs.writeFileSync(path.join(__dirname, 'sqlite-migration.js'), migrationCode);
console.log('✅ Arquivo de migração criado: sqlite-migration.js');

console.log('\n🎯 Próximos passos:');
console.log('1. Execute: npm install');
console.log('2. Atualize o código conforme sqlite-migration.js');
console.log('3. Teste a aplicação');
console.log('4. Para reverter: cp package.json.backup package.json');

console.log('\n✅ Correção concluída!');