import RichTextEditor from '../../shared/RichTextEditor';

interface Props {
  content: string;
  onChange: (html: string) => void;
  placeholder?: string;
}

export default function BlogEditor({ content, onChange, placeholder = 'Escreva o conteúdo do post...' }: Props) {
  return (
    <RichTextEditor
      content={content}
      onChange={onChange}
      toolbar="full"
      placeholder={placeholder}
      minHeight="300px"
    />
  );
}
