const express = require('express');
const router = express.Router();
const { db } = require('../handlers/db.js');
const { isAuthenticated } = require('../handlers/auth.js');

/**
 * GET /instances
 * Renders the instances page with active avisos
 */
router.get('/instances', isAuthenticated, async (req, res) => {
  try {
    console.log('Loading instances page...');
    // Buscar avisos ativos
    let avisos = await db.get('avisos');
    console.log('Raw avisos from DB:', avisos);
    avisos = avisos ? JSON.parse(avisos) : [];
    console.log('Parsed avisos:', avisos);
    avisos.forEach((aviso, index) => {
      console.log(`Aviso ${index}: ativo = ${aviso.ativo} (type: ${typeof aviso.ativo})`);
    });
    const avisosAtivos = avisos.filter(aviso => aviso.ativo === true);
    console.log('Active avisos:', avisosAtivos);

    // Buscar outras informações necessárias para a página
    const name = await db.get('name') || 'DracoPanel';
    const logo = await db.get('logo') || false;

    console.log('Rendering instances page with avisos:', avisosAtivos);
    res.render('instances', {
      req,
      user: req.user,
      name,
      logo,
      avisos: avisosAtivos
    });
  } catch (err) {
    console.error('Error loading instances page:', err);
    res.status(500).send('Internal Server Error');
  }
});

module.exports = router;