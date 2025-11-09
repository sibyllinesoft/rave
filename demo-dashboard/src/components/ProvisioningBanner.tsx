import React from 'react';
import { VMEstimate } from '../types';
import * as Icons from 'lucide-react';

interface ProvisioningBannerProps {
  estimate: VMEstimate;
  selectedServicesCount: number;
  onProvision: () => void;
  isVisible: boolean;
}

export const ProvisioningBanner: React.FC<ProvisioningBannerProps> = ({
  estimate,
  selectedServicesCount,
  onProvision,
  isVisible
}) => {
  if (!isVisible || selectedServicesCount === 0) return null;

  return (
    <div className="fixed bottom-0 left-0 right-0 z-40 bg-graphite-900/95 backdrop-blur border-t border-graphite-700 transform transition-transform duration-300">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
        <div className="flex items-center justify-between">
          {/* Left: Quick Stats */}
          <div className="flex items-center space-x-6">
            <div className="flex items-center space-x-2">
              <Icons.Layers className="w-4 h-4 text-accent-400" />
              <span className="text-sm text-graphite-300">
                {selectedServicesCount} services
              </span>
            </div>
            
            <div className="flex items-center space-x-4 text-xs text-graphite-400 font-mono">
              <span className="flex items-center space-x-1">
                <Icons.Cpu className="w-3 h-3" />
                <span>{estimate.totalCpu}c</span>
              </span>
              <span className="flex items-center space-x-1">
                <Icons.HardDrive className="w-3 h-3" />
                <span>{estimate.totalMemory}GB</span>
              </span>
              <span className="flex items-center space-x-1">
                <Icons.Database className="w-3 h-3" />
                <span>{estimate.totalStorage}GB</span>
              </span>
            </div>
          </div>

          {/* Center: Instance & Cost */}
          <div className="hidden md:flex items-center space-x-6">
            <div className="text-center">
              <div className="text-xs text-graphite-500">Recommended</div>
              <div className="text-sm font-medium text-graphite-200">
                {estimate.recommendedInstanceType.split(' ')[0]}
              </div>
            </div>
            
            <div className="text-center">
              <div className="text-xs text-graphite-500">Monthly Cost</div>
              <div className="text-lg font-semibold text-accent-400">
                ${estimate.estimatedCost.toFixed(0)}
              </div>
            </div>
          </div>

          {/* Right: Action */}
          <div className="flex items-center space-x-3">
            {/* Mobile cost display */}
            <div className="md:hidden">
              <div className="text-lg font-semibold text-accent-400">
                ${estimate.estimatedCost.toFixed(0)}/mo
              </div>
            </div>
            
            {/* Warnings indicator */}
            {estimate.warnings.length > 0 && (
              <div className="relative group">
                <Icons.AlertTriangle className="w-5 h-5 text-yellow-500" />
                <div className="absolute bottom-full right-0 mb-2 w-64 bg-graphite-800 border border-graphite-600 rounded-lg p-3 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
                  <div className="text-xs text-yellow-400 space-y-1">
                    {estimate.warnings.map((warning, index) => (
                      <div key={index}>• {warning}</div>
                    ))}
                  </div>
                </div>
              </div>
            )}
            
            <button
              onClick={onProvision}
              className="bg-accent-600 text-white px-6 py-2 rounded-lg font-medium hover:bg-accent-700 transition-colors flex items-center space-x-2"
            >
              <Icons.Rocket className="w-4 h-4" />
              <span>Provision</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
