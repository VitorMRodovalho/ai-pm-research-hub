import { useState, useEffect } from 'react';
import BlogEditor from './BlogEditor';

/**
 * Island wrapper that bridges between vanilla JS (blog admin page)
 * and the React TipTap editor.
 *
 * Listens for 'blog:editor:set' custom events to load content,
 * and dispatches 'blog:editor:change' when content changes.
 */
export default function BlogEditorIsland() {
  const [content, setContent] = useState('');

  useEffect(() => {
    const onSet = (e: Event) => {
      const html = (e as CustomEvent).detail || '';
      setContent(html);
    };
    window.addEventListener('blog:editor:set', onSet);
    return () => window.removeEventListener('blog:editor:set', onSet);
  }, []);

  const handleChange = (html: string) => {
    setContent(html);
    window.dispatchEvent(new CustomEvent('blog:editor:change', { detail: html }));
  };

  return <BlogEditor content={content} onChange={handleChange} />;
}
