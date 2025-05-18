import type { IconButtonProps } from '@mui/material/IconButton';

import { useState, useEffect, useCallback } from 'react';
import closeIcon from '@iconify-icons/mingcute/close-line';
import settingsIcon from '@iconify-icons/solar/settings-bold-duotone';

import Box from '@mui/material/Box';
import Stack from '@mui/material/Stack';
import Drawer from '@mui/material/Drawer';
import SvgIcon from '@mui/material/SvgIcon';
import MenuItem from '@mui/material/MenuItem';
import { alpha, useTheme } from '@mui/material/styles';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import Divider from '@mui/material/Divider';

import { paths } from 'src/routes/paths';
import { useRouter, usePathname } from 'src/routes/hooks';

import { Label } from 'src/components/label';
import { Iconify } from 'src/components/iconify';
import { Scrollbar } from 'src/components/scrollbar';
import { AnimateAvatar } from 'src/components/animate';

import { getOrgLogo, getOrgIdFromToken } from 'src/sections/accountdetails/utils';

import { useAuthContext } from 'src/auth/hooks';

import { AccountButton } from './account-button';
import { SignOutButton } from './sign-out-button';
// ----------------------------------------------------------------------

// Base account menu items
const baseAccountItems = [
  {
    label: 'Manage my profile',
    href: '/account/company-settings/personal-profile',
    icon: (
      <SvgIcon>
        <path
          opacity="0.5"
          d="M2.28099 19.6575C2.36966 20.5161 2.93261 21.1957 3.77688 21.3755C5.1095 21.6592 7.6216 22 12 22C16.3784 22 18.8905 21.6592 20.2232 21.3755C21.0674 21.1957 21.6303 20.5161 21.719 19.6575C21.8505 18.3844 22 16.0469 22 12C22 7.95305 21.8505 5.6156 21.719 4.34251C21.6303 3.48389 21.0674 2.80424 20.2231 2.62451C18.8905 2.34081 16.3784 2 12 2C7.6216 2 5.1095 2.34081 3.77688 2.62451C2.93261 2.80424 2.36966 3.48389 2.28099 4.34251C2.14952 5.6156 2 7.95305 2 12C2 16.0469 2.14952 18.3844 2.28099 19.6575Z"
          fill="currentColor"
        />
        <path
          d="M13.9382 13.8559C15.263 13.1583 16.1663 11.7679 16.1663 10.1666C16.1663 7.8655 14.3008 6 11.9996 6C9.69841 6 7.83291 7.8655 7.83291 10.1666C7.83291 11.768 8.73626 13.1584 10.0612 13.856C8.28691 14.532 6.93216 16.1092 6.51251 18.0529C6.45446 18.3219 6.60246 18.5981 6.87341 18.6471C7.84581 18.8231 9.45616 19 12.0006 19C14.545 19 16.1554 18.8231 17.1278 18.6471C17.3977 18.5983 17.5454 18.3231 17.4876 18.0551C17.0685 16.1103 15.7133 14.5321 13.9382 13.8559Z"
          fill="currentColor"
        />
      </SvgIcon>
    ),
  },
];

// Company settings menu item (only for business accounts)
const companySettingsItem = {
  label: 'Company Settings',
  href: '/account/company-settings/profile',
  icon: <Iconify icon={settingsIcon} />,
};

export type AccountDrawerProps = IconButtonProps & {
  data?: {
    label: string;
    href: string;
    icon?: React.ReactNode;
    info?: React.ReactNode;
  }[];
};

export function AccountDrawer({ data = [], sx, ...other }: AccountDrawerProps) {
  const theme = useTheme();
  const router = useRouter();
  const pathname = usePathname();
  const { user } = useAuthContext();
  const isDark = theme.palette.mode === 'dark';

  const [open, setOpen] = useState(false);
  const [menuItems, setMenuItems] = useState(data);
  const [customLogo, setCustomLogo] = useState<string | null>('');
  const isBusiness =
    user?.accountType === 'business' ||
    user?.accountType === 'organization' ||
    user?.role === 'business';
    
  useEffect(() => {
    const fetchLogo = async () => {
      try {
        const orgId = await getOrgIdFromToken();
        if (isBusiness) {
          const logoUrl = await getOrgLogo(orgId);
          setCustomLogo(logoUrl);
        }
      } catch (err) {
        console.error(err, 'error in fetching logo');
      }
    };
    fetchLogo();
  }, [isBusiness]);

  // Build menu items when user data changes
  useEffect(() => {
    // If data is provided through props, use it
    if (data && data.length > 0) {
      setMenuItems(data);
      return;
    }

    // Otherwise build based on account type
    const items = [...baseAccountItems];

    if (isBusiness) {
      items.push(companySettingsItem);
    }

    setMenuItems(items);
  }, [data, isBusiness]);

  const handleOpenDrawer = useCallback(() => {
    setOpen(true);
  }, []);

  const handleCloseDrawer = useCallback(() => {
    setOpen(false);
  }, []);

  const handleClickItem = useCallback(
    (path: string) => {
      handleCloseDrawer();
      router.push(path);
    },
    [handleCloseDrawer, router]
  );

  const renderAvatar = (
    <AnimateAvatar
      width={86}
      slotProps={{
        avatar: { src: user?.photoURL, alt: user?.displayName },
        overlay: {
          border: isDark ? 1 : 2,
          spacing: 2.5,
          color: `linear-gradient(135deg, ${alpha(theme.palette.primary.main, 0.1)} 25%, ${alpha(theme.palette.primary.main, 0.8)} 100%)`,
        },
      }}
    >
      {user?.displayName?.charAt(0).toUpperCase() || user?.fullName?.charAt(0).toUpperCase() || 'U'}
    </AnimateAvatar>
  );

  return (
    <>
      <AccountButton
        onClick={handleOpenDrawer}
        photoURL={customLogo || user?.photoURL}
        displayName={user?.fullName}
        sx={sx}
        {...other}
      />

      <Drawer
        open={open}
        onClose={handleCloseDrawer}
        anchor="right"
        slotProps={{ 
          backdrop: { 
            invisible: false,
            sx: { 
              backdropFilter: 'blur(1px)',
              backgroundColor: isDark ? alpha('#111', 0.1) : alpha('#fff', 0.6)
            }
          } 
        }}
        PaperProps={{ 
          sx: { 
            width: 300,
            borderRadius: isDark ? '12px 0 0 12px' : '16px 0 0 16px',
            boxShadow: isDark 
              ? '0 0 24px rgba(0, 0, 0, 0.3)'
              : '0 0 24px rgba(0, 0, 0, 0.1)',
            backgroundColor: isDark ? alpha(theme.palette.background.default, 0.95) : theme.palette.background.default,
            backgroundImage: isDark 
              ? 'linear-gradient(180deg, rgba(22, 28, 36, 0.8) 0%, rgba(22, 28, 36, 0.95) 100%)' 
              : 'none',
          } 
        }}
      >
        <IconButton
          onClick={handleCloseDrawer}
          sx={{ 
            top: 16, 
            left: 16, 
            zIndex: 9, 
            position: 'absolute',
            color: 'text.secondary',
            backgroundColor: isDark ? alpha(theme.palette.background.paper, 0.3) : alpha(theme.palette.background.paper, 0.8),
            boxShadow: isDark 
              ? '0 2px 6px rgba(0, 0, 0, 0.2)'
              : '0 2px 8px rgba(0, 0, 0, 0.05)',
            backdropFilter: 'blur(8px)',
            '&:hover': {
              backgroundColor: isDark ? alpha(theme.palette.background.paper, 0.5) : alpha(theme.palette.background.paper, 1),
            },
            transition: 'all 0.2s ease-in-out',
          }}
        >
          <Iconify icon={closeIcon} />
        </IconButton>

        <Scrollbar>
          <Stack alignItems="center" sx={{ pt: 9, pb: 2 }}>
            {renderAvatar}

            <Typography 
              variant="subtitle1" 
              noWrap 
              sx={{ 
                mt: 2.5, 
                fontWeight: 600,
                letterSpacing: '0.01em',
              }}
            >
              {user?.fullName || user?.displayName}
            </Typography>

            <Typography 
              variant="body2" 
              sx={{ 
                color: 'text.secondary', 
                mt: 0.5,
                fontSize: '0.8125rem',
                opacity: 0.85,
              }} 
              noWrap
            >
              {user?.email}
            </Typography>

            {/* Show account type if available */}
            {user?.accountType && (
              <Label
                color={
                  user.accountType === 'business' || user.accountType === 'organization'
                    ? 'primary'
                    : 'info'
                }
                sx={{ 
                  mt: 1.5,
                  px: 1,
                  py: 0.5,
                  fontSize: '0.7rem',
                  fontWeight: 500,
                  borderRadius: '4px',
                  letterSpacing: '0.02em',
                  textTransform: 'uppercase',
                  backgroundColor: isDark 
                    ? alpha(theme.palette.primary.main, 0.16)
                    : alpha(theme.palette.primary.main, 0.08),
                  color: isDark
                    ? alpha(theme.palette.primary.main, 0.9)
                    : theme.palette.primary.main,
                }}
              >
                {user.accountType === 'business' || user.accountType === 'organization'
                  ? 'Business Account'
                  : 'Individual Account'}
              </Label>
            )}
          </Stack>

          <Box sx={{ px: 2, mt: 1 }}>
            <Divider 
              sx={{ 
                my: 2,
                opacity: isDark ? 0.2 : 0.4,
                borderStyle: 'dashed',
              }}
            />
            
            <Stack spacing={0.25}>
              {menuItems.map((option) => {
                const rootLabel = pathname.includes('/dashboard') ? 'Home' : 'Dashboard';
                const rootHref = pathname.includes('/dashboard') ? '/' : paths.dashboard.root;
                const isActive = pathname === (option.label === 'Home' ? rootHref : option.href);

                return (
                  <MenuItem
                    key={option.label}
                    onClick={() => handleClickItem(option.label === 'Home' ? rootHref : option.href)}
                    sx={{
                      height: 44,
                      borderRadius: 1.5,
                      mb: 0.5,
                      py: 1,
                      px: 1.5,
                      color: isActive ? 'primary.main' : 'text.secondary',
                      backgroundColor: isActive 
                        ? isDark 
                          ? alpha(theme.palette.primary.main, 0.16) 
                          : alpha(theme.palette.primary.main, 0.08)
                        : 'transparent',
                      '& svg': { 
                        width: 20, 
                        height: 20,
                        color: isActive ? 'primary.main' : 'text.secondary',
                        opacity: isDark ? 0.9 : 0.7,
                      },
                      '&:hover': { 
                        backgroundColor: isActive 
                          ? isDark 
                            ? alpha(theme.palette.primary.main, 0.24) 
                            : alpha(theme.palette.primary.main, 0.12)
                          : isDark 
                            ? alpha(theme.palette.action.hover, 0.4) 
                            : theme.palette.action.hover,
                        color: isActive ? 'primary.main' : 'text.primary',
                      },
                      transition: 'all 0.2s ease-in-out',
                    }}
                  >
                    <Box sx={{ 
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      width: 32,
                      height: 32,
                      mr: 1.5,
                      borderRadius: 1,
                      backgroundColor: isActive 
                        ? isDark 
                          ? alpha(theme.palette.primary.main, 0.24) 
                          : alpha(theme.palette.primary.main, 0.12)
                        : isDark
                          ? alpha(theme.palette.action.hover, 0.2)
                          : alpha(theme.palette.action.hover, 0.4),
                    }}>
                      {option.icon}
                    </Box>

                    <Typography
                      variant="body2"
                      sx={{
                        fontWeight: isActive ? 600 : 400,
                        flex: 1,
                      }}
                    >
                      {option.label === 'Home' ? rootLabel : option.label}
                    </Typography>

                    {option.info && (
                      <Label 
                        color="error" 
                        sx={{ 
                          ml: 1,
                          fontSize: '0.65rem',
                          height: 18,
                        }}
                      >
                        {option.info}
                      </Label>
                    )}
                  </MenuItem>
                );
              })}
            </Stack>
          </Box>
        </Scrollbar>

        <Box sx={{ p: 2.5, mt: 1 }}>
          <SignOutButton onClose={handleCloseDrawer} />
        </Box>
      </Drawer>
    </>
  );
}