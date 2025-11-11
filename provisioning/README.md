# RAVE Provisioning Dashboard

A React-based demo application for showcasing RAVE's service provisioning capabilities. This dashboard allows users to select services, configure their company details, and get VM resource estimates for their development environment.

## Features

- **Service Selection**: Choose from 11+ available RAVE services organized by category
- **Smart Dependencies**: Automatic handling of service dependencies and warnings
- **Company Configuration**: Detailed form to capture usage patterns and team size
- **Resource Estimation**: Intelligent VM sizing based on selected services and company details
- **Cost Estimation**: Monthly cost calculations with optimization suggestions
- **Responsive Design**: Modern UI with Tailwind CSS and Lucide React icons

## Available Services

### Core Infrastructure
- PostgreSQL - Relational database
- Redis - In-memory data store
- nginx - Web server and reverse proxy

### Development Tools
- GitLab - Complete DevOps platform
- NATS - Messaging system
- n8n - Workflow automation

### Monitoring & Observability
- Grafana - Monitoring dashboards
- Prometheus - Metrics collection

### Design & Prototyping
- Penpot - Open-source design platform

### Team Collaboration
- Mattermost - Open-source team communication platform
- Outline - Team wiki and knowledge base

## Getting Started

### Prerequisites
- Node.js 18+ and npm
- Modern web browser

### Installation

1. Navigate to the demo dashboard directory:
   ```bash
   cd demo-dashboard
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Start the development server:
   ```bash
   npm run dev
   ```

4. Open your browser to `http://localhost:5173`

## Usage

### Step 1: Service Selection
- Browse services organized by category (Core, Development, Monitoring, Design, Collaboration)
- Click services to add/remove them from your configuration
- Dependencies are automatically detected and warnings shown
- Resource usage (CPU, Memory, Storage) displayed for each service

### Step 2: Company Details
- Enter your company name and team size
- Select development intensity (Light, Moderate, Heavy)
- Choose CI/CD usage level (Minimal, Moderate, Extensive)
- Define project complexity (Simple, Medium, Complex)
- Specify concurrent users and expected growth

### Step 3: Estimation & Provisioning
- Review selected services and resource calculations
- See total CPU cores, memory, and storage requirements
- View recommended instance type and monthly cost estimate
- Get optimization suggestions and performance warnings
- Simulate VM provisioning (demo only - no actual provisioning)

## Technology Stack

- **React 18** with TypeScript
- **Vite** for build tooling and development server
- **Tailwind CSS** for styling and responsive design
- **Lucide React** for consistent iconography

## Demo Data

The dashboard includes realistic service data matching actual RAVE capabilities:
- Resource usage based on real-world service requirements
- Cost estimates using industry-standard pricing models
- Dependencies reflect actual service relationships in RAVE

## Demo Limitations

This is a **demonstration application only**:
- No actual VM provisioning occurs
- Cost estimates are illustrative
- No backend integration
- Local data storage only

For actual RAVE provisioning, use the production RAVE CLI and infrastructure.