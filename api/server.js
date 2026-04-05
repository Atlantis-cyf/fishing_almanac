'use strict';

/**
 * Vercel Serverless entry for the Express BFF (must live under api/).
 * Static Flutter web is served from build/web via vercel.json outputDirectory.
 */
module.exports = require('../backend/server.js');
