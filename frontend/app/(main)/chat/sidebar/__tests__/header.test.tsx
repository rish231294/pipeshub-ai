import React from 'react';
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, cleanup, fireEvent } from '@testing-library/react';
import { Theme } from '@radix-ui/themes';
import '@/lib/__tests__/test-i18n';

vi.mock('@/lib/navigation', () => ({
  Link: ({ href, onClick, children, ...rest }: React.AnchorHTMLAttributes<HTMLAnchorElement>) => (
    <a
      href={href}
      onClick={(e) => {
        e.preventDefault();
        onClick?.(e);
      }}
      {...rest}
    >
      {children}
    </a>
  ),
}));
vi.mock('@/config', () => ({ BrandMark: () => <span>logo</span> }));
vi.mock('@/app/components/ui/user-avatar', () => ({ UserAvatar: () => null }));
vi.mock('@/app/components/ui/MaterialIcon', () => ({ MaterialIcon: () => null }));

import { ChatSidebarHeader } from '../header';
import { useChatStore } from '@/chat/store';

afterEach(() => {
  cleanup();
  useChatStore.getState().setMode('chat');
});

function renderHeader() {
  return render(
    <Theme>
      <ChatSidebarHeader />
    </Theme>,
  );
}

describe('Chat sidebar header: Home', () => {
  it('links the logo to /chat/', () => {
    renderHeader();
    expect(screen.getByRole('link', { name: 'Home' }).getAttribute('href')).toBe('/chat/');
  });

  it('leaves search results when Home is clicked, since both live on /chat/', () => {
    const clearSearchResults = vi.spyOn(useChatStore.getState(), 'clearSearchResults');
    useChatStore.getState().setMode('search');
    renderHeader();

    fireEvent.click(screen.getByRole('link', { name: 'Home' }));

    expect(useChatStore.getState().settings.mode).toBe('chat');
    expect(clearSearchResults).toHaveBeenCalledOnce();
  });
});
