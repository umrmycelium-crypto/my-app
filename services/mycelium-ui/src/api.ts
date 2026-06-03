import axios from 'axios';

const RULE_ENGINE_URL = import.meta.env.VITE_RULE_ENGINE_URL || 'http://localhost:8080';

export interface Detection {
  entity_id?: string;
  type: string;
  attributes: Record<string, any>;
  confidence: number;
}

export interface Feedback {
  rule_id: string;
  feedback: 'contradiction' | 'confirm' | 'ignore';
  entity_id?: string;
  reason?: string;
}

export const api = {
  getHealth: async () => {
    try {
      const response = await axios.get(`${RULE_ENGINE_URL}/health`);
      return response.data;
    } catch (e) {
      return { status: 'unhealthy', error: String(e) };
    }
  },
  
  detect: async (payload: Detection) => {
    const response = await axios.post(`${RULE_ENGINE_URL}/api/v1/detect`, payload);
    return response.data;
  },
  
  matchRules: async (payload: any) => {
    const response = await axios.post(`${RULE_ENGINE_URL}/api/v1/rules/match`, payload);
    return response.data;
  },
  
  sendFeedback: async (payload: Feedback) => {
    const response = await axios.post(`${RULE_ENGINE_URL}/api/v1/feedback`, payload);
    return response.data;
  },
  
  getPendingRules: async () => {
    const response = await axios.get(`${RULE_ENGINE_URL}/api/v1/rules/pending`);
    return response.data;
  }
};
