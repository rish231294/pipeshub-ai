export interface ConnectorConfig {
  id: string;
  icon: string;
  title: string;
  description: string;
  color: string;
}

export interface ConfigStatus {
  googleWorkspace: boolean;
}
export const GOOGLE_WORKSPACE_SCOPE = [
  'https://www.googleapis.com/auth/drive',
  'https://www.googleapis.com/auth/gmail.readonly',
  'https://www.googleapis.com/auth/calendar',
].join(' ');

// Define available connectors
export const CONNECTORS_LIST: ConnectorConfig[] = [
  {
    id: 'googleWorkspace',
    icon: 'mdi:google',
    title: 'Google Workspace',
    description:
      'Integrate with Google Workspace for calendar, gmail, spreadsheets, drive and document sharing',
    color: '#4285F4',
  },
];
