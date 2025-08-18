#!/usr/bin/env node

/**
 * Vibe Kanban MCP Server
 * Provides integration between Claude and Vibe Kanban
 */

const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const axios = require('axios');

class VibeKanbanMCPServer {
  constructor() {
    this.server = new Server({
      name: 'vibe-kanban',
      version: '1.0.0'
    }, {
      capabilities: {
        tools: {}
      }
    });

    this.baseUrl = process.env.VIBE_KANBAN_URL || 'http://localhost:3000';
    this.apiKey = process.env.VIBE_KANBAN_API_KEY || '';
    
    this.setupTools();
  }

  setupTools() {
    // Get all boards
    this.server.setRequestHandler('tools/list', async () => {
      return {
        tools: [
          {
            name: 'get_boards',
            description: 'Get all Kanban boards',
            inputSchema: {
              type: 'object',
              properties: {},
              required: []
            }
          },
          {
            name: 'get_board',
            description: 'Get a specific board by ID',
            inputSchema: {
              type: 'object',
              properties: {
                boardId: {
                  type: 'string',
                  description: 'The ID of the board'
                }
              },
              required: ['boardId']
            }
          },
          {
            name: 'create_card',
            description: 'Create a new card in a board',
            inputSchema: {
              type: 'object',
              properties: {
                boardId: {
                  type: 'string',
                  description: 'The ID of the board'
                },
                listId: {
                  type: 'string',
                  description: 'The ID of the list (column)'
                },
                title: {
                  type: 'string',
                  description: 'The title of the card'
                },
                description: {
                  type: 'string',
                  description: 'The description of the card'
                }
              },
              required: ['boardId', 'listId', 'title']
            }
          },
          {
            name: 'update_card',
            description: 'Update an existing card',
            inputSchema: {
              type: 'object',
              properties: {
                cardId: {
                  type: 'string',
                  description: 'The ID of the card'
                },
                title: {
                  type: 'string',
                  description: 'New title for the card'
                },
                description: {
                  type: 'string',
                  description: 'New description for the card'
                },
                listId: {
                  type: 'string',
                  description: 'New list ID to move the card'
                }
              },
              required: ['cardId']
            }
          },
          {
            name: 'delete_card',
            description: 'Delete a card',
            inputSchema: {
              type: 'object',
              properties: {
                cardId: {
                  type: 'string',
                  description: 'The ID of the card to delete'
                }
              },
              required: ['cardId']
            }
          }
        ]
      };
    });

    // Handle tool calls
    this.server.setRequestHandler('tools/call', async (request) => {
      const { name, arguments: args } = request.params;

      try {
        switch (name) {
          case 'get_boards':
            return await this.getBoards();
          case 'get_board':
            return await this.getBoard(args.boardId);
          case 'create_card':
            return await this.createCard(args);
          case 'update_card':
            return await this.updateCard(args);
          case 'delete_card':
            return await this.deleteCard(args.cardId);
          default:
            throw new Error(`Unknown tool: ${name}`);
        }
      } catch (error) {
        return {
          content: [{
            type: 'text',
            text: `Error: ${error.message}`
          }],
          isError: true
        };
      }
    });
  }

  async makeRequest(method, endpoint, data = null) {
    const config = {
      method,
      url: `${this.baseUrl}${endpoint}`,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    if (this.apiKey) {
      config.headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    if (data) {
      config.data = data;
    }

    const response = await axios(config);
    return response.data;
  }

  async getBoards() {
    const boards = await this.makeRequest('GET', '/api/boards');
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(boards, null, 2)
      }]
    };
  }

  async getBoard(boardId) {
    const board = await this.makeRequest('GET', `/api/boards/${boardId}`);
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(board, null, 2)
      }]
    };
  }

  async createCard(args) {
    const card = await this.makeRequest('POST', `/api/boards/${args.boardId}/cards`, {
      listId: args.listId,
      title: args.title,
      description: args.description || ''
    });
    return {
      content: [{
        type: 'text',
        text: `Card created successfully: ${JSON.stringify(card, null, 2)}`
      }]
    };
  }

  async updateCard(args) {
    const updateData = {};
    if (args.title) updateData.title = args.title;
    if (args.description) updateData.description = args.description;
    if (args.listId) updateData.listId = args.listId;

    const card = await this.makeRequest('PUT', `/api/cards/${args.cardId}`, updateData);
    return {
      content: [{
        type: 'text',
        text: `Card updated successfully: ${JSON.stringify(card, null, 2)}`
      }]
    };
  }

  async deleteCard(cardId) {
    await this.makeRequest('DELETE', `/api/cards/${cardId}`);
    return {
      content: [{
        type: 'text',
        text: `Card ${cardId} deleted successfully`
      }]
    };
  }

  async run() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Vibe Kanban MCP server running on stdio');
  }
}

// Start the server
const server = new VibeKanbanMCPServer();
server.run().catch(console.error);