import React from 'react';
import { VMEstimate } from '../types';
import * as Icons from 'lucide-react';

interface EstimationResultsProps {
  estimate: VMEstimate;
  onProvision: () => void;
}

export const EstimationResults: React.FC<EstimationResultsProps> = ({
  estimate,
  onProvision
}) => {
  return (
    <div className="bg-white rounded-lg shadow-sm border p-6">
      <div className="flex items-center space-x-3 mb-6">
        <div className="p-2 bg-green-100 rounded-lg">
          <Icons.Calculator className="w-5 h-5 text-green-600" />
        </div>
        <div>
          <h2 className="text-xl font-semibold text-gray-900">VM Estimation</h2>
          <p className="text-sm text-gray-600">Resource requirements and cost estimate</p>
        </div>
      </div>

      {/* Resource Summary */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div className="bg-blue-50 rounded-lg p-4">
          <div className="flex items-center space-x-2 mb-2">
            <Icons.Cpu className="w-4 h-4 text-blue-600" />
            <span className="text-sm font-medium text-blue-900">CPU Cores</span>
          </div>
          <div className="text-2xl font-bold text-blue-900">{estimate.totalCpu}</div>
        </div>

        <div className="bg-purple-50 rounded-lg p-4">
          <div className="flex items-center space-x-2 mb-2">
            <Icons.HardDrive className="w-4 h-4 text-purple-600" />
            <span className="text-sm font-medium text-purple-900">Memory</span>
          </div>
          <div className="text-2xl font-bold text-purple-900">{estimate.totalMemory} GB</div>
        </div>

        <div className="bg-green-50 rounded-lg p-4">
          <div className="flex items-center space-x-2 mb-2">
            <Icons.Database className="w-4 h-4 text-green-600" />
            <span className="text-sm font-medium text-green-900">Storage</span>
          </div>
          <div className="text-2xl font-bold text-green-900">{estimate.totalStorage} GB</div>
        </div>
      </div>

      {/* Instance Type and Cost */}
      <div className="bg-gradient-to-r from-rave-50 to-blue-50 rounded-lg p-6 mb-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <div className="flex items-center space-x-2 mb-2">
              <Icons.Server className="w-5 h-5 text-rave-600" />
              <span className="font-semibold text-rave-900">Recommended Instance</span>
            </div>
            <div className="text-lg text-rave-800">{estimate.recommendedInstanceType}</div>
          </div>
          
          <div>
            <div className="flex items-center space-x-2 mb-2">
              <Icons.DollarSign className="w-5 h-5 text-rave-600" />
              <span className="font-semibold text-rave-900">Estimated Monthly Cost</span>
            </div>
            <div className="text-2xl font-bold text-rave-900">
              ${estimate.estimatedCost.toFixed(0)}
            </div>
            <div className="text-xs text-rave-700 mt-1">
              Includes compute, storage, and estimated usage
            </div>
          </div>
        </div>
      </div>

      {/* Warnings */}
      {estimate.warnings.length > 0 && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 mb-4">
          <div className="flex items-start space-x-2">
            <Icons.AlertTriangle className="w-5 h-5 text-yellow-600 mt-0.5 flex-shrink-0" />
            <div>
              <h3 className="font-medium text-yellow-900 mb-2">Warnings</h3>
              <ul className="space-y-1">
                {estimate.warnings.map((warning, index) => (
                  <li key={index} className="text-sm text-yellow-800">
                    • {warning}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      )}

      {/* Optimizations */}
      {estimate.optimizations.length > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
          <div className="flex items-start space-x-2">
            <Icons.Lightbulb className="w-5 h-5 text-blue-600 mt-0.5 flex-shrink-0" />
            <div>
              <h3 className="font-medium text-blue-900 mb-2">Optimization Suggestions</h3>
              <ul className="space-y-1">
                {estimate.optimizations.map((optimization, index) => (
                  <li key={index} className="text-sm text-blue-800">
                    • {optimization}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      )}

      {/* Provision Button */}
      <div className="flex items-center justify-between">
        <div className="text-sm text-gray-600">
          Ready to provision your RAVE development environment?
        </div>
        <button
          onClick={onProvision}
          className="bg-rave-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-rave-700 transition-colors flex items-center space-x-2"
        >
          <Icons.Rocket className="w-4 h-4" />
          <span>Provision VM</span>
        </button>
      </div>
    </div>
  );
};