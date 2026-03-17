import { useState, useEffect } from 'react';
import RichTextEditor from './RichTextEditor';

interface Props {
  fieldName: string;
  toolbar?: 'full' | 'basic' | 'minimal';
  placeholder?: string;
  minHeight?: string;
}

/**
 * Generic Astro island wrapper for RichTextEditor.
 *
 * Listens for `richtext:{fieldName}:set` to load content,
 * dispatches `richtext:{fieldName}:change` when content changes.
 */
export default function RichTextEditorIsland({
  fieldName,
  toolbar = 'basic',
  placeholder,
  minHeight,
}: Props) {
  const [content, setContent] = useState('');

  useEffect(() => {
    const onSet = (e: Event) => {
      const html = (e as CustomEvent).detail || '';
      setContent(html);
    };
    window.addEventListener(`richtext:${fieldName}:set`, onSet);
    return () => window.removeEventListener(`richtext:${fieldName}:set`, onSet);
  }, [fieldName]);

  const handleChange = (html: string) => {
    setContent(html);
    window.dispatchEvent(
      new CustomEvent(`richtext:${fieldName}:change`, { detail: html }),
    );
  };

  return (
    <RichTextEditor
      content={content}
      onChange={handleChange}
      toolbar={toolbar}
      placeholder={placeholder}
      minHeight={minHeight}
    />
  );
}
