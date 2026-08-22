import { describe, it, expect, beforeEach, vi } from 'vitest';
import { apiClient } from '@/lib/api';
import { ChatApi } from '../api';

vi.mock('@/lib/api', () => ({
  apiClient: {
    get: vi.fn(),
    post: vi.fn(),
    put: vi.fn(),
    delete: vi.fn(),
  },
  streamSSERequest: vi.fn(),
}));

import { streamSSERequest } from '@/lib/api';
import { useLanguageStore } from '@/lib/store/language-store';
import type { StreamChatRequest, StreamMessageCallbacks } from '../types';

vi.mock('@/lib/i18n/config', () => ({ default: { changeLanguage: vi.fn() } }));

const mockedGet = vi.mocked(apiClient.get);
const mockedStream = vi.mocked(streamSSERequest);

describe('ChatApi stream bodies — responseLanguage', () => {
  const baseRequest: StreamChatRequest = {
    query: 'hello',
    modelKey: 'k1',
    modelName: 'gpt-5',
    modelFriendlyName: 'GPT 5',
    chatMode: 'internal_search',
    filters: { apps: [], kb: [] },
  };
  const callbacks: StreamMessageCallbacks = {};

  beforeEach(() => {
    mockedStream.mockReset();
    mockedStream.mockResolvedValue(undefined);
    useLanguageStore.setState({ language: 'en-US' });
  });

  function lastBody(): Record<string, unknown> {
    expect(mockedStream).toHaveBeenCalledTimes(1);
    return mockedStream.mock.calls[0][1] as Record<string, unknown>;
  }

  it('omits responseLanguage when the Language setting is the default', async () => {
    await ChatApi.streamMessage(baseRequest, callbacks);
    const body = lastBody();
    expect(body).not.toHaveProperty('responseLanguage', expect.any(String));
    expect(body.timezone).toEqual(expect.any(String));
  });

  it('sends responseLanguage on the universal stream body once a language is chosen', async () => {
    useLanguageStore.setState({ language: 'de-DE' });
    await ChatApi.streamMessage(baseRequest, callbacks);
    expect(lastBody().responseLanguage).toBe('de-DE');
  });

  it('sends responseLanguage on the agent stream body', async () => {
    useLanguageStore.setState({ language: 'es-ES' });
    await ChatApi.streamMessage({ ...baseRequest, agentId: 'agent-1', chatMode: 'agent:auto' }, callbacks);
    expect(mockedStream.mock.calls[0][0]).toContain('/api/v1/agents/agent-1/');
    expect(lastBody().responseLanguage).toBe('es-ES');
  });

  it('sends responseLanguage on both regenerate bodies', async () => {
    useLanguageStore.setState({ language: 'hi-IN' });
    await ChatApi.streamRegenerate('conv-1', 'msg-1', callbacks, baseRequest);
    expect(lastBody().responseLanguage).toBe('hi-IN');

    mockedStream.mockClear();
    await ChatApi.streamAgentRegenerate('agent-1', 'conv-1', 'msg-1', callbacks, {
      modelKey: 'k1',
      modelName: 'gpt-5',
      chatMode: 'auto',
      filters: { apps: [], kb: [] },
    });
    expect(lastBody().responseLanguage).toBe('hi-IN');
  });
});

describe('ChatApi.fetchAvailableLlms', () => {
  beforeEach(() => {
    mockedGet.mockReset();
  });

  it('returns the models array on a well-formed response', async () => {
    const models = [{ modelKey: 'k1', modelName: 'gpt-5', provider: 'openai' }];
    mockedGet.mockResolvedValueOnce({ data: { status: 'success', models, message: '' } });
    const result = await ChatApi.fetchAvailableLlms();
    expect(result).toEqual(models);
  });

  it('returns an empty array when the response body is null', async () => {
    mockedGet.mockResolvedValueOnce({ data: null });
    const result = await ChatApi.fetchAvailableLlms();
    expect(result).toEqual([]);
  });

  it('returns an empty array when the response body is undefined', async () => {
    mockedGet.mockResolvedValueOnce({ data: undefined });
    const result = await ChatApi.fetchAvailableLlms();
    expect(result).toEqual([]);
  });

  it('returns an empty array when models is missing', async () => {
    mockedGet.mockResolvedValueOnce({ data: { status: 'success', message: '' } });
    const result = await ChatApi.fetchAvailableLlms();
    expect(result).toEqual([]);
  });

  it('returns an empty array when models is a malformed non-array value', async () => {
    mockedGet.mockResolvedValueOnce({ data: { status: 'success', models: { oops: true }, message: '' } });
    const result = await ChatApi.fetchAvailableLlms();
    expect(result).toEqual([]);
  });
});
