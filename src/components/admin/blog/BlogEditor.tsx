import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import Link from '@tiptap/extension-link';
import Image from '@tiptap/extension-image';
import Placeholder from '@tiptap/extension-placeholder';
import { useEffect } from 'react';

interface Props {
  content: string;
  onChange: (html: string) => void;
  placeholder?: string;
}

export default function BlogEditor({ content, onChange, placeholder = 'Escreva o conteúdo do post...' }: Props) {
  const editor = useEditor({
    extensions: [
      StarterKit.configure({
        heading: { levels: [2, 3] },
      }),
      Link.configure({ openOnClick: false, HTMLAttributes: { class: 'text-teal underline' } }),
      Image.configure({ inline: false, allowBase64: false }),
      Placeholder.configure({ placeholder }),
    ],
    content: content || '',
    onUpdate: ({ editor: e }) => {
      onChange(e.getHTML());
    },
  });

  // Sync external content changes (e.g., language tab switch)
  useEffect(() => {
    if (editor && content !== editor.getHTML()) {
      editor.commands.setContent(content || '');
    }
  }, [content]);

  if (!editor) return null;

  const btn = (label: string, active: boolean, onClick: () => void, title: string) => (
    <button
      type="button"
      onClick={onClick}
      title={title}
      className={`px-2 py-1 text-xs font-semibold rounded cursor-pointer border-0 transition-colors ${
        active
          ? 'bg-teal-600 text-white'
          : 'bg-[var(--surface-hover)] text-[var(--text-secondary)] hover:bg-[var(--surface-base)]'
      }`}
    >
      {label}
    </button>
  );

  const addLink = () => {
    const url = window.prompt('URL:');
    if (url) {
      editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run();
    }
  };

  const addImage = () => {
    const url = window.prompt('Image URL:');
    if (url) {
      editor.chain().focus().setImage({ src: url }).run();
    }
  };

  return (
    <div className="border border-[var(--border-default)] rounded-lg overflow-hidden">
      {/* Toolbar */}
      <div className="flex flex-wrap gap-1 px-2 py-1.5 border-b border-[var(--border-default)] bg-[var(--surface-section-cool)]">
        {btn('B', editor.isActive('bold'), () => editor.chain().focus().toggleBold().run(), 'Negrito')}
        {btn('I', editor.isActive('italic'), () => editor.chain().focus().toggleItalic().run(), 'Itálico')}
        {btn('H2', editor.isActive('heading', { level: 2 }), () => editor.chain().focus().toggleHeading({ level: 2 }).run(), 'Heading 2')}
        {btn('H3', editor.isActive('heading', { level: 3 }), () => editor.chain().focus().toggleHeading({ level: 3 }).run(), 'Heading 3')}
        <span className="w-px bg-[var(--border-default)] mx-0.5" />
        {btn('•', editor.isActive('bulletList'), () => editor.chain().focus().toggleBulletList().run(), 'Lista')}
        {btn('1.', editor.isActive('orderedList'), () => editor.chain().focus().toggleOrderedList().run(), 'Lista numerada')}
        <span className="w-px bg-[var(--border-default)] mx-0.5" />
        {btn('Link', editor.isActive('link'), addLink, 'Link')}
        {btn('Img', false, addImage, 'Imagem (URL)')}
        {btn('</>', editor.isActive('codeBlock'), () => editor.chain().focus().toggleCodeBlock().run(), 'Bloco de código')}
        {btn('—', false, () => editor.chain().focus().setHorizontalRule().run(), 'Linha horizontal')}
      </div>

      {/* Editor */}
      <EditorContent
        editor={editor}
        className="blog-tiptap-editor prose prose-sm max-w-none min-h-[300px] px-4 py-3 text-[var(--text-primary)] bg-[var(--surface-base)] focus-within:outline-none"
      />

      <style>{`
        .blog-tiptap-editor .tiptap {
          min-height: 280px;
          outline: none;
        }
        .blog-tiptap-editor .tiptap p.is-editor-empty:first-child::before {
          content: attr(data-placeholder);
          float: left;
          color: var(--text-muted, #aaa);
          pointer-events: none;
          height: 0;
        }
        .blog-tiptap-editor .tiptap h2 { font-size: 1.25rem; font-weight: 700; margin: 1rem 0 0.5rem; }
        .blog-tiptap-editor .tiptap h3 { font-size: 1.1rem; font-weight: 600; margin: 0.75rem 0 0.5rem; }
        .blog-tiptap-editor .tiptap ul { list-style: disc; padding-left: 1.5rem; }
        .blog-tiptap-editor .tiptap ol { list-style: decimal; padding-left: 1.5rem; }
        .blog-tiptap-editor .tiptap blockquote { border-left: 3px solid var(--border-default, #ccc); padding-left: 1rem; color: var(--text-secondary); }
        .blog-tiptap-editor .tiptap pre { background: var(--surface-section-cool, #f5f5f5); padding: 0.75rem; border-radius: 0.5rem; overflow-x: auto; font-size: 0.8rem; }
        .blog-tiptap-editor .tiptap code { background: var(--surface-section-cool, #f5f5f5); padding: 0.15rem 0.3rem; border-radius: 0.25rem; font-size: 0.85em; }
        .blog-tiptap-editor .tiptap img { max-width: 100%; height: auto; border-radius: 0.5rem; margin: 0.5rem 0; }
        .blog-tiptap-editor .tiptap hr { border: none; border-top: 1px solid var(--border-default, #ccc); margin: 1rem 0; }
        .blog-tiptap-editor .tiptap a { color: #0d9488; text-decoration: underline; }
      `}</style>
    </div>
  );
}
