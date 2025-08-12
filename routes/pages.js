/**
 * @fileoverview This module dynamically sets up express routes for different pages based on
 * configuration read from a JSON file. It utilizes middleware for authentication checks and
 * accesses a database to fetch user-specific or global information to render pages.
 */

const express = require('express');
const fs = require('fs').promises;
const router = express.Router();
const config = require('../config.json')

const { isAuthenticated } = require('../handlers/auth.js');
const { db } = require('../handlers/db.js');

/**
 * Dynamically reads the page configurations from a JSON file and sets up express routes accordingly.
 * Each page configuration can specify if authentication is required. Authenticated routes fetch
 * user-specific instance data from the database, while non-authenticated routes fetch general data.
 * Routes render pages with the specified templates and data.
 *
 * @async
 * @function setupRoutes
 * @returns {Promise<void>} Executes the asynchronous setup of routes, does not return a value but logs errors.
 */

async function setupRoutes() {
    try {
        const data = await fs.readFile('pages.json', 'utf8'); 
        const pages = JSON.parse(data);

        pages.forEach(async page => {
            if (page.requiresAuth) {
                router.get(page.path, isAuthenticated, async (req, res) => {
                    try {
                        const userId = req.user.userId;
                        let instances = await db.get(userId + '_instances') || [];
                        let adminInstances = [];
                        if (req.user.admin) {
                            const allInstances = await db.get('instances') || [];
                            adminInstances = allInstances.filter(instance => instance.User == userId);
                        }
                
                        const users = await db.get('users') || [];
                
                        const authenticatedUser = users.find(user => user.userId === userId);
                        if (!authenticatedUser) {
                            throw new Error('Authenticated user not found in database.');
                        }
                        const subUserInstances = authenticatedUser.accessTo || [];
                        for (const instanceId of subUserInstances) {
                            const instanceData = await db.get(`${instanceId}_instance`);
                            if (instanceData) {
                                instances.push(instanceData);
                            }
                        }
                        
                        // Get user plan information
                        const userPlan = authenticatedUser.plan || 'Gratuito';
                        const plans = {
                            'Gratuito': { projects: 1, ram: 512, storage: 1 },
                            'Iniciante': { projects: 5, ram: 3072, storage: 9 },
                            'Intermediário': { projects: 15, ram: 10240, storage: 20 },
                            'Super': { projects: 30, ram: 20480, storage: 30 }
                        };
                        
                        // Calculate current usage
                        const currentRamUsage = instances.reduce((total, instance) => total + (instance.ramUsage || 0), 0);
                        const currentStorageUsage = instances.reduce((total, instance) => total + (instance.storageUsage || 0), 0);
                        
                        const planData = {
                            current: userPlan,
                            limits: plans[userPlan],
                            usage: {
                                projects: instances.length,
                                ram: currentRamUsage,
                                storage: currentStorageUsage
                            },
                            available: {
                                projects: Math.max(0, plans[userPlan].projects - instances.length),
                                ram: Math.max(0, plans[userPlan].ram - currentRamUsage),
                                storage: Math.max(0, plans[userPlan].storage - currentStorageUsage)
                            },
                            allPlans: plans
                        };
                        
                        // Get available nodes and images for project creation
                        const nodeIds = await db.get('nodes') || [];
                        console.log('Node IDs:', nodeIds);
                        const nodes = await Promise.all(
                            nodeIds.map(async (id) => {
                                const node = await db.get(id + '_node');
                                console.log(`Node ${id}:`, node);
                                return node;
                            })
                        ).then(nodes => nodes.filter(node => node !== null && node !== undefined));
                        console.log('Filtered nodes:', nodes);
                        const images = await db.get('images') || [];
                
                        res.render(page.template, { 
                            req, 
                            user: req.user, 
                            name: await db.get('name') || 'DracoPanel', 
                            logo: await db.get('logo') || false,
                            settings: await db.get('settings'),
                            config, 
                            instances, 
                            adminInstances,
                            planData,
                            nodes,
                            images
                        });
                    } catch (error) {
                        console.error('Error fetching subuser instances:', error);
                        res.status(500).send('Internal Server Error');
                    }
                });
                
                
            } else {
                router.get(page.path, async (req, res) => {
                    res.render(page.template, {
                        req,
                        name: await db.get('name') || 'DracoPanel',
                        logo: await db.get('logo') || false,
                        settings: await db.get('settings')
                    });
                });
            }
        });
    } catch (error) {
        console.error('Error setting up routes:', error);
    }
}

/**
 * GET /
 * Redirects the user to the instances overview page. This route serves as a default route that
 * directs users to a more specific page, handling the initial access or any unspecified routes.
 *
 * @returns {Response} Redirects to the '/instances' page.
 */

router.get('/', async (req, res) => {
    res.redirect('../instances')
});

// Setup routes
setupRoutes();

module.exports = router;
