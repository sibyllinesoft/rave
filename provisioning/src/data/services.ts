import { Service } from '../types';

export const availableServices: Service[] = [
  {
    id: 'gitlab',
    name: 'GitLab',
    description: 'Complete DevOps platform with Git repositories, CI/CD, and project management',
    icon: 'GitBranch',
    category: 'core',
    resourceUsage: {
      cpu: 2,
      memory: 4,
      storage: 25,
    },
    scaling: {
      concurrentUsers: { cpu: 0.1, memory: 0.18, storage: 0.3 },
      cicdIntensity: { cpu: 0.9, memory: 1.2, storage: 3 },
      teamSize: { cpu: 0.05, memory: 0.08, storage: 0.25 },
    },
    requirements: ['PostgreSQL', 'Redis'],
  },
  {
    id: 'postgresql',
    name: 'PostgreSQL',
    description: 'Powerful open-source relational database system',
    icon: 'Database',
    category: 'core',
    resourceUsage: {
      cpu: 2,
      memory: 2,
      storage: 60,
    },
    scaling: {
      concurrentUsers: { cpu: 0.03, memory: 0.06, storage: 0.8 },
      teamSize: { cpu: 0.02, memory: 0.05, storage: 0.6 },
    },
  },
  {
    id: 'redis',
    name: 'Redis',
    description: 'In-memory data structure store for caching and sessions',
    icon: 'Zap',
    category: 'core',
    resourceUsage: {
      cpu: 0.5,
      memory: 2,
      storage: 6,
    },
    scaling: {
      concurrentUsers: { cpu: 0.02, memory: 0.05 },
      teamSize: { memory: 0.03 },
    },
  },
  {
    id: 'nginx',
    name: 'Nginx',
    description: 'High-performance web server and reverse proxy',
    icon: 'Globe',
    category: 'core',
    resourceUsage: {
      cpu: 0.5,
      memory: 0.5,
      storage: 3,
    },
    scaling: {
      concurrentUsers: { cpu: 0.005, memory: 0.01 },
    },
  },
  {
    id: 'pomerium',
    name: 'Pomerium',
    description: 'Identity-aware proxy that adds OAuth and policy controls',
    icon: 'ShieldCheck',
    category: 'security',
    resourceUsage: {
      cpu: 0.5,
      memory: 1,
      storage: 4,
    },
    scaling: {
      concurrentUsers: { cpu: 0.01, memory: 0.02 },
      teamSize: { storage: 0.05 },
    },
    requirements: ['GitLab', 'Nginx'],
  },
  {
    id: 'grafana',
    name: 'Grafana',
    description: 'Monitoring and observability platform with dashboards and alerting',
    icon: 'BarChart3',
    category: 'monitoring',
    resourceUsage: {
      cpu: 1,
      memory: 2,
      storage: 10,
    },
    scaling: {
      concurrentUsers: { cpu: 0.02, memory: 0.05, storage: 0.2 },
    },
  },
  {
    id: 'prometheus',
    name: 'Prometheus',
    description: 'Time-series monitoring system with alerting capabilities',
    icon: 'Activity',
    category: 'monitoring',
    resourceUsage: {
      cpu: 2,
      memory: 4,
      storage: 50,
    },
    scaling: {
      concurrentUsers: { cpu: 0.04, memory: 0.1, storage: 1.5 },
      teamSize: { storage: 1 },
    },
  },
  {
    id: 'nats',
    name: 'NATS',
    description: 'High-performance messaging system for microservices',
    icon: 'MessageSquare',
    category: 'development',
    resourceUsage: {
      cpu: 1,
      memory: 1,
      storage: 5,
    },
    scaling: {
      concurrentUsers: { cpu: 0.02, memory: 0.03 },
    },
  },
  {
    id: 'penpot',
    name: 'Penpot',
    description: 'Open-source design and prototyping platform',
    icon: 'Palette',
    category: 'design',
    resourceUsage: {
      cpu: 2,
      memory: 4,
      storage: 50,
    },
    scaling: {
      concurrentUsers: { cpu: 0.04, memory: 0.08, storage: 1 },
      teamSize: { storage: 0.8 },
    },
    requirements: ['PostgreSQL', 'Redis'],
  },
  {
    id: 'mattermost',
    name: 'Mattermost',
    description: 'Open-source team communication and collaboration platform',
    icon: 'MessageCircle',
    category: 'collaboration',
    resourceUsage: {
      cpu: 2,
      memory: 4,
      storage: 20,
    },
    scaling: {
      concurrentUsers: { cpu: 0.05, memory: 0.07, storage: 0.5 },
      teamSize: { storage: 0.4 },
    },
    requirements: ['PostgreSQL'],
  },
  {
    id: 'outline',
    name: 'Outline',
    description: 'Team wiki and knowledge base with real-time collaboration',
    icon: 'BookOpen',
    category: 'collaboration',
    resourceUsage: {
      cpu: 1,
      memory: 1,
      storage: 10,
    },
    scaling: {
      teamSize: { storage: 0.3 },
    },
    requirements: ['PostgreSQL', 'Redis'],
  },
  {
    id: 'n8n',
    name: 'n8n',
    description: 'Workflow automation tool for connecting apps and services',
    icon: 'Workflow',
    category: 'development',
    resourceUsage: {
      cpu: 1,
      memory: 2,
      storage: 20,
    },
    scaling: {
      concurrentUsers: { cpu: 0.03, memory: 0.05, storage: 0.3 },
      teamSize: { storage: 0.2 },
    },
  },
];
