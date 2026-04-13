import { useState, useCallback, useRef } from 'react';
import type { AttendanceGridData, CellStatus, CheckInResult, ToggleResult } from '../components/attendance/types';

interface UseAttendanceOptions {
  supabase: any;
  /** @deprecated Use initiativeId instead */
  tribeId?: number;
  initiativeId?: string;
}

export function useAttendance({ supabase, tribeId, initiativeId }: UseAttendanceOptions) {
  const [grid, setGrid] = useState<AttendanceGridData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const optimistic = useRef<Map<string, CellStatus>>(new Map());

  const fetchGrid = useCallback(async (filterType?: string | null) => {
    setLoading(true);
    setError(null);
    try {
      const params: any = {};
      // Prefer initiative_id; fall back to tribe_id
      let rpcName: string;
      if (initiativeId) {
        params.p_initiative_id = initiativeId;
        if (filterType) params.p_event_type = filterType;
        rpcName = 'get_initiative_attendance_grid';
      } else if (tribeId) {
        params.p_tribe_id = tribeId;
        if (filterType) params.p_event_type = filterType;
        rpcName = 'get_tribe_attendance_grid';
      } else {
        if (filterType) params.p_event_type = filterType;
        rpcName = 'get_attendance_grid';
      }
      const { data, error: rpcError } = await supabase.rpc(rpcName, params);

      if (rpcError) throw rpcError;
      if (data?.error) throw new Error(data.error);

      optimistic.current.clear();
      setGrid(data);
    } catch (err: any) {
      setError(err.message || 'Failed to load attendance');
    } finally {
      setLoading(false);
    }
  }, [supabase, tribeId, initiativeId]);

  const toggleMember = useCallback(async (
    eventId: string,
    memberId: string,
    currentStatus: CellStatus
  ): Promise<ToggleResult> => {
    if (currentStatus === 'na') return { success: false, error: 'permission_denied' };

    const newPresent = currentStatus !== 'present';
    const cellKey = `${eventId}:${memberId}`;
    const newStatus: CellStatus = newPresent ? 'present' : 'absent';

    optimistic.current.set(cellKey, newStatus);
    setGrid(prev => prev ? { ...prev } : null);

    try {
      const { data, error: rpcError } = await supabase.rpc('mark_member_present', {
        p_event_id: eventId,
        p_member_id: memberId,
        p_present: newPresent,
      });

      if (rpcError) throw rpcError;
      if (data && !data.success) {
        optimistic.current.delete(cellKey);
        setGrid(prev => prev ? { ...prev } : null);
        return { success: false, error: data.error, message: data.message };
      }

      return { success: true, marked: 1 };
    } catch (err: any) {
      optimistic.current.delete(cellKey);
      setGrid(prev => prev ? { ...prev } : null);
      return { success: false, error: 'permission_denied', message: err.message };
    }
  }, [supabase]);

  const selfCheckIn = useCallback(async (eventId: string): Promise<CheckInResult> => {
    try {
      const { data, error: rpcError } = await supabase.rpc('register_own_presence', {
        p_event_id: eventId,
      });

      if (rpcError) throw rpcError;

      if (data?.success) {
        await fetchGrid();
        return { success: true };
      }

      return { success: false, error: data?.error, message: data?.message };
    } catch (err: any) {
      return { success: false, error: 'not_authenticated', message: err.message };
    }
  }, [supabase, fetchGrid]);

  const batchToggle = useCallback(async (
    eventId: string,
    memberIds: string[],
    present: boolean
  ): Promise<ToggleResult> => {
    try {
      const { data, error: rpcError } = await supabase.rpc('admin_bulk_mark_attendance', {
        p_event_id: eventId,
        p_member_ids: memberIds,
        p_present: present,
      });

      if (rpcError) throw rpcError;

      if (data?.success) {
        await fetchGrid();
        return { success: true, marked: data.marked };
      }

      return { success: false, error: data?.error, message: data?.message };
    } catch (err: any) {
      return { success: false, error: 'permission_denied', message: err.message };
    }
  }, [supabase, fetchGrid]);

  const getEffectiveStatus = useCallback((
    eventId: string,
    memberId: string,
    serverStatus: CellStatus
  ): CellStatus => {
    const key = `${eventId}:${memberId}`;
    return optimistic.current.get(key) ?? serverStatus;
  }, []);

  return {
    grid,
    loading,
    error,
    fetchGrid,
    toggleMember,
    selfCheckIn,
    batchToggle,
    getEffectiveStatus,
  };
}
