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
    // Buscar avisos ativos
    let avisos = await db.get('avisos');
    avisos = avisos ? JSON.parse(avisos) : [];
    const avisosAtivos = avisos.filter(aviso => aviso.ativo);

    // Buscar outras informações necessárias para a página
    const name = await db.get('name') || 'DracoPanel';
    const logo = await db.get('logo') || false;

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