import { Icon } from '@iconify/react';
import { Page, pdfjs, Document } from 'react-pdf';
import { useState, useEffect, useCallback } from 'react';
import { useResizeObserver } from '@wojtekmaj/react-hooks';

import { 
  Box, 
  Fade, 
  Stack,
  Dialog,
  Tooltip,
  Skeleton,
  IconButton,
  Typography,
  DialogTitle,
  DialogContent,
  CircularProgress
} from '@mui/material';

pdfjs.GlobalWorkerOptions.workerSrc = `//cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjs.version}/pdf.worker.min.js`;

const resizeObserverOptions = {};
const maxWidth = 800;

interface PDFViewerProps {
  open : boolean;
  onClose : () => void;
  pdfUrl : string;
  fileName : string;
}

interface DocumentLoadSuccess {
  numPages: number;
}

const PageLoader = () => (
  <Box sx={{ width: '100%', display: 'flex', justifyContent: 'center' }}>
    <Box sx={{ width: maxWidth, position: 'relative' }}>
      <Skeleton 
        variant="rectangular" 
        width="100%" 
        height={500}
        sx={{ 
          borderRadius: 1,
          bgcolor: 'grey.100'
        }}
      />
      <Box 
        sx={{ 
          position: 'absolute',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          display: 'flex',
          alignItems: 'center',
          gap: 1
        }}
      >
        <CircularProgress size={20} thickness={4} />
        <Typography 
          variant="body2" 
          color="text.secondary"
        >
          Loading document...
        </Typography>
      </Box>
    </Box>
  </Box>
);

export default function PDFViewer({ open, onClose, pdfUrl, fileName } : PDFViewerProps) {
  const [numPages, setNumPages] = useState<number>(0);
  // eslint-disable-next-line
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [containerRef, setContainerRef] = useState<HTMLElement | null>(null);
  const [containerWidth, setContainerWidth] = useState<number | undefined>();
  const [loading, setLoading] = useState<boolean>(true);
  const [scale, setScale] = useState<number>(1);
  const [error, setError] = useState<string | null>(null);
  const [key, setKey] = useState<number>(0);

  console.log(pdfUrl)
  // Reset states when URL changes
  useEffect(() => {
    if (pdfUrl) {
      setLoading(true);
      setError(null);
      setNumPages(0);
      setCurrentPage(1);
      setScale(1);
      setKey(prev => prev + 1); // Force Document component to reload
    }
  }, [pdfUrl]);

  // Cleanup function
  useEffect(() => () => {
    setNumPages(0);
    setCurrentPage(1);
    setScale(1);
    setError(null);
    setLoading(true);
  }, []);

  const onResize = useCallback((entries : ResizeObserverEntry[]) => {
    const [entry] = entries;
    if (entry) {
      setContainerWidth(entry.contentRect.width);
    }
  }, []);

  useResizeObserver(containerRef, resizeObserverOptions, onResize);

  const onDocumentLoadSuccess = useCallback(({ numPages: nextNumPages }: DocumentLoadSuccess) => {
    setNumPages(nextNumPages);
    setLoading(false);
    setError(null);
  }, []);

  const onDocumentLoadError = useCallback((err : Error) => {
    setError('Failed to load PDF. Please try again.');
    setLoading(false);
  }, []);

  const handleZoomIn = useCallback(() => {
    setScale(prevScale => Math.min(prevScale + 0.1, 2));
  }, []);

  const handleZoomOut = useCallback(() => {
    setScale(prevScale => Math.max(prevScale - 0.1, 0.5));
  }, []);

  const handleRetry = useCallback(() => {
    setLoading(true);
    setError(null);
    setKey(prev => prev + 1);
  }, []);


  if (!pdfUrl) {
    return null;
  }

  return (
    <Dialog 
      open={open} 
      onClose={onClose}
      maxWidth="lg"
      fullWidth
      TransitionComponent={Fade}
      PaperProps={{
        sx: { 
          minHeight: '90vh',
          maxHeight: '90vh',
          bgcolor: 'background.default'
        }
      }}
    >
      <DialogTitle 
        sx={{ 
          display: 'flex', 
          justifyContent: 'space-between', 
          alignItems: 'center',
          borderBottom: '1px solid',
          borderColor: 'divider',
          p: 2,
          bgcolor: 'background.paper'
        }}
      >
        <Stack direction="row" spacing={1} alignItems="center">
          <Icon icon="mdi:file-document-outline" style={{ fontSize: '24px' }} />
          <Typography variant="h6" noWrap>{fileName}</Typography>
          {loading && (
            <CircularProgress size={16} thickness={4} sx={{ ml: 2 }} />
          )}
        </Stack>
        <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
          <Tooltip title="Zoom out">
            <IconButton 
              onClick={handleZoomOut}
              size="small"
              disabled={scale <= 0.5 || loading}
            >
              <Icon icon="mdi:minus" />
            </IconButton>
          </Tooltip>
          <Typography 
            variant="body2" 
            sx={{ 
              minWidth: '40px', 
              textAlign: 'center',
              color: 'text.secondary'
            }}
          >
            {Math.round(scale * 100)}%
          </Typography>
          <Tooltip title="Zoom in">
            <IconButton 
              onClick={handleZoomIn}
              size="small"
              disabled={scale >= 2 || loading}
            >
              <Icon icon="mdi:plus" />
            </IconButton>
          </Tooltip>
          <Tooltip title="Close">
            <IconButton 
              onClick={onClose}
              size="small"
              sx={{ ml: 1 }}
            >
              <Icon icon="mdi:close" />
            </IconButton>
          </Tooltip>
        </Box>
      </DialogTitle>

      <DialogContent sx={{ p: 0 }}>
        <Box 
          ref={setContainerRef} 
          sx={{ 
            overflow: 'auto',
            height: '100%',
            px: 2,
            py: 3,
            bgcolor: 'grey.50'
          }}
        >
          {error ? (
            <Box 
              sx={{ 
                p: 4, 
                textAlign: 'center',
                borderRadius: 2,
                bgcolor: 'error.lighter',
                color: 'error.main',
                mt: 4
              }}
            >
              <Icon 
                icon="mdi:alert-circle-outline" 
                style={{ fontSize: '48px' }} 
              />
              <Typography 
                variant="h6" 
                sx={{ mt: 2, color: 'error.main' }}
              >
                {error}
              </Typography>
              <Typography 
                variant="body2" 
                color="error.dark" 
                sx={{ mt: 1, mb: 2 }}
              >
                The document might be inaccessible or the URL might have expired
              </Typography>
              <Tooltip title="Try loading again">
                <IconButton 
                  onClick={handleRetry}
                  color="primary"
                  sx={{ 
                    bgcolor: 'background.paper',
                    '&:hover': { bgcolor: 'background.paper' }
                  }}
                >
                  <Icon icon="mdi:refresh" />
                </IconButton>
              </Tooltip>
            </Box>
          ) : (
            <Document 
              key={key}
              file={pdfUrl} 
              onLoadSuccess={onDocumentLoadSuccess}
              onLoadError={onDocumentLoadError}
              loading={<PageLoader />}
            >
              {Array.from(new Array(numPages), (_, index) => (
                <Fade in={!loading} key={`page_${index + 1}`}>
                  <Box 
                    sx={{
                      display: 'flex',
                      justifyContent: 'center',
                      mb: 2,
                      '&:last-child': { mb: 0 },
                      boxShadow: '0 4px 24px rgba(0,0,0,0.06)',
                      borderRadius: 1,
                      bgcolor: 'background.paper',
                      overflow: 'hidden'
                    }}
                  >
                    <Page
                      pageNumber={index + 1}
                      width={containerWidth ? Math.min(containerWidth * scale, maxWidth * scale) : maxWidth * scale}
                      loading={<PageLoader />}
                      renderAnnotationLayer={false}
                      renderTextLayer={false}
                    />
                  </Box>
                </Fade>
              ))}
            </Document>
          )}
        </Box>
      </DialogContent>
    </Dialog>
  );
} 