# Feature Spec: Gerenciamento de Instancias de Eventos Recorrentes

## Status: In Progress

## Problema
Eventos recorrentes sao criados individualmente no banco, mas quando uma reuniao nao acontece ou e deslocada de data, ninguem consegue deletar ou editar aquela instancia pela plataforma.

## RPCs

### drop_event_instance(p_event_id uuid)
- Auth: tribe_leader do evento OU manager/deputy_manager/is_superadmin
- Rejeitar se attendance count > 0
- Rejeitar se meeting_artifacts, cost_entries, cpmai_sessions, webinars, event_showcases count > 0
- CASCADE automatico: attendance, event_tag_assignments, event_audience_rules, event_invited_members, meeting_action_items
- Return: { success, deleted_event_id, deleted_date }

### update_event_instance(p_event_id uuid, p_new_date date, p_new_time_start time, p_notes text)
- Auth: mesmo do delete
- Campos editaveis: date, time_start, duration_minutes, meeting_link, notes, agenda_text
- Validacao: p_new_date nao pode conflitar com outro evento da mesma tribo no mesmo dia
- Return: { success, updated_fields }

## Frontend
- Icone de acoes por evento na lista de attendance/admin
- "Cancelar esta reuniao" -> confirm dialog -> drop_event_instance
- "Editar esta reuniao" -> modal com campos editaveis -> update_event_instance

## Permissao frontend
```js
const canManageEvent = (member, event) =>
  member.is_superadmin ||
  member.operational_role === 'manager' ||
  member.operational_role === 'deputy_manager' ||
  (member.operational_role === 'tribe_leader' && member.tribe_id === event.tribe_id);
```
