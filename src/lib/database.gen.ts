export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.4"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      admin_audit_log: {
        Row: {
          action: string
          actor_id: string | null
          changes: Json | null
          created_at: string | null
          id: string
          metadata: Json | null
          target_id: string | null
          target_type: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          changes?: Json | null
          created_at?: string | null
          id?: string
          metadata?: Json | null
          target_id?: string | null
          target_type?: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          changes?: Json | null
          created_at?: string | null
          id?: string
          metadata?: Json | null
          target_id?: string | null
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "admin_audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "admin_audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "admin_audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_links: {
        Row: {
          category: string
          created_at: string
          created_by: string | null
          description: string | null
          icon: string | null
          id: number
          is_active: boolean
          sort_order: number | null
          title: string
          updated_at: string
          url: string
        }
        Insert: {
          category: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          icon?: string | null
          id?: number
          is_active?: boolean
          sort_order?: number | null
          title: string
          updated_at?: string
          url: string
        }
        Update: {
          category?: string
          created_at?: string
          created_by?: string | null
          description?: string | null
          icon?: string | null
          id?: number
          is_active?: boolean
          sort_order?: number | null
          title?: string
          updated_at?: string
          url?: string
        }
        Relationships: []
      }
      ai_analysis_runs: {
        Row: {
          ai_analysis_snapshot: Json | null
          application_id: string
          completed_at: string | null
          duration_ms: number | null
          error_message: string | null
          fields_changed: string[] | null
          id: string
          input_token_estimate: number | null
          model_version: string
          organization_id: string
          output_token_estimate: number | null
          run_index: number
          started_at: string
          status: string
          triggered_by: string
        }
        Insert: {
          ai_analysis_snapshot?: Json | null
          application_id: string
          completed_at?: string | null
          duration_ms?: number | null
          error_message?: string | null
          fields_changed?: string[] | null
          id?: string
          input_token_estimate?: number | null
          model_version?: string
          organization_id?: string
          output_token_estimate?: number | null
          run_index: number
          started_at?: string
          status?: string
          triggered_by: string
        }
        Update: {
          ai_analysis_snapshot?: Json | null
          application_id?: string
          completed_at?: string | null
          duration_ms?: number | null
          error_message?: string | null
          fields_changed?: string[] | null
          id?: string
          input_token_estimate?: number | null
          model_version?: string
          organization_id?: string
          output_token_estimate?: number | null
          run_index?: number
          started_at?: string
          status?: string
          triggered_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_analysis_runs_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_calibration_runs: {
        Row: {
          cycle_id: string | null
          drift_count_high: number
          drift_threshold: number
          id: string
          mean_delta_abs: number | null
          mean_delta_signed: number | null
          n_compared: number
          organization_id: string
          ran_at: string
          sample_payload: Json | null
          triggered_by: string
          validator_breakdown: Json | null
        }
        Insert: {
          cycle_id?: string | null
          drift_count_high?: number
          drift_threshold?: number
          id?: string
          mean_delta_abs?: number | null
          mean_delta_signed?: number | null
          n_compared?: number
          organization_id?: string
          ran_at?: string
          sample_payload?: Json | null
          triggered_by?: string
          validator_breakdown?: Json | null
        }
        Update: {
          cycle_id?: string | null
          drift_count_high?: number
          drift_threshold?: number
          id?: string
          mean_delta_abs?: number | null
          mean_delta_signed?: number | null
          n_compared?: number
          organization_id?: string
          ran_at?: string
          sample_payload?: Json | null
          triggered_by?: string
          validator_breakdown?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "ai_calibration_runs_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "selection_cycles"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_processing_log: {
        Row: {
          application_id: string
          cache_creation_tokens: number | null
          cache_read_tokens: number | null
          caller_member_id: string | null
          completed_at: string | null
          created_at: string
          duration_ms: number | null
          error_message: string | null
          id: string
          input_tokens: number | null
          model_id: string
          model_provider: string
          organization_id: string
          output_tokens: number | null
          prompt_hash: string | null
          purpose: string
          response_hash: string | null
          status: string
          triggered_by: string
        }
        Insert: {
          application_id: string
          cache_creation_tokens?: number | null
          cache_read_tokens?: number | null
          caller_member_id?: string | null
          completed_at?: string | null
          created_at?: string
          duration_ms?: number | null
          error_message?: string | null
          id?: string
          input_tokens?: number | null
          model_id: string
          model_provider: string
          organization_id?: string
          output_tokens?: number | null
          prompt_hash?: string | null
          purpose: string
          response_hash?: string | null
          status?: string
          triggered_by: string
        }
        Update: {
          application_id?: string
          cache_creation_tokens?: number | null
          cache_read_tokens?: number | null
          caller_member_id?: string | null
          completed_at?: string | null
          created_at?: string
          duration_ms?: number | null
          error_message?: string | null
          id?: string
          input_tokens?: number | null
          model_id?: string
          model_provider?: string
          organization_id?: string
          output_tokens?: number | null
          prompt_hash?: string | null
          purpose?: string
          response_hash?: string | null
          status?: string
          triggered_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_processing_log_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_processing_log_caller_member_id_fkey"
            columns: ["caller_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_processing_log_caller_member_id_fkey"
            columns: ["caller_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ai_processing_log_caller_member_id_fkey"
            columns: ["caller_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_processing_log_caller_member_id_fkey"
            columns: ["caller_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_processing_log_caller_member_id_fkey"
            columns: ["caller_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_score_validations: {
        Row: {
          ai_model: string | null
          ai_purpose: string
          ai_score: number | null
          ai_verdict: string | null
          application_id: string
          comment: string | null
          id: string
          organization_id: string
          override_score: number | null
          validated_at: string
          validation_action: string
          validator_id: string
        }
        Insert: {
          ai_model?: string | null
          ai_purpose: string
          ai_score?: number | null
          ai_verdict?: string | null
          application_id: string
          comment?: string | null
          id?: string
          organization_id?: string
          override_score?: number | null
          validated_at?: string
          validation_action: string
          validator_id: string
        }
        Update: {
          ai_model?: string | null
          ai_purpose?: string
          ai_score?: number | null
          ai_verdict?: string | null
          application_id?: string
          comment?: string | null
          id?: string
          organization_id?: string
          override_score?: number | null
          validated_at?: string
          validation_action?: string
          validator_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ai_score_validations_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_score_validations_validator_id_fkey"
            columns: ["validator_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_score_validations_validator_id_fkey"
            columns: ["validator_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ai_score_validations_validator_id_fkey"
            columns: ["validator_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_score_validations_validator_id_fkey"
            columns: ["validator_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ai_score_validations_validator_id_fkey"
            columns: ["validator_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      analysis_results: {
        Row: {
          analysis_type: string
          created_at: string | null
          id: string
          project_id: string | null
          results: Json | null
          user_id: string | null
        }
        Insert: {
          analysis_type: string
          created_at?: string | null
          id?: string
          project_id?: string | null
          results?: Json | null
          user_id?: string | null
        }
        Update: {
          analysis_type?: string
          created_at?: string | null
          id?: string
          project_id?: string | null
          results?: Json | null
          user_id?: string | null
        }
        Relationships: []
      }
      announcements: {
        Row: {
          created_at: string | null
          created_by: string | null
          ends_at: string | null
          id: string
          initiative_id: string | null
          is_active: boolean | null
          link_text: string | null
          link_url: string | null
          message: string | null
          message_en: string | null
          message_es: string | null
          organization_id: string
          starts_at: string | null
          title: string
          title_en: string | null
          title_es: string | null
          type: string | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          ends_at?: string | null
          id?: string
          initiative_id?: string | null
          is_active?: boolean | null
          link_text?: string | null
          link_url?: string | null
          message?: string | null
          message_en?: string | null
          message_es?: string | null
          organization_id?: string
          starts_at?: string | null
          title: string
          title_en?: string | null
          title_es?: string | null
          type?: string | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          ends_at?: string | null
          id?: string
          initiative_id?: string | null
          is_active?: boolean | null
          link_text?: string | null
          link_url?: string | null
          message?: string | null
          message_en?: string | null
          message_es?: string | null
          organization_id?: string
          starts_at?: string | null
          title?: string
          title_en?: string | null
          title_es?: string | null
          type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      annual_kpi_targets: {
        Row: {
          auto_query: string | null
          baseline_value: number | null
          category: string
          created_at: string | null
          current_value: number | null
          cycle: number
          display_order: number | null
          icon: string | null
          id: string
          kpi_key: string
          kpi_label_en: string | null
          kpi_label_es: string | null
          kpi_label_pt: string
          notes: string | null
          organization_id: string
          target_unit: string
          target_value: number
          updated_at: string | null
          year: number
        }
        Insert: {
          auto_query?: string | null
          baseline_value?: number | null
          category?: string
          created_at?: string | null
          current_value?: number | null
          cycle?: number
          display_order?: number | null
          icon?: string | null
          id?: string
          kpi_key: string
          kpi_label_en?: string | null
          kpi_label_es?: string | null
          kpi_label_pt: string
          notes?: string | null
          organization_id?: string
          target_unit?: string
          target_value: number
          updated_at?: string | null
          year?: number
        }
        Update: {
          auto_query?: string | null
          baseline_value?: number | null
          category?: string
          created_at?: string | null
          current_value?: number | null
          cycle?: number
          display_order?: number | null
          icon?: string | null
          id?: string
          kpi_key?: string
          kpi_label_en?: string | null
          kpi_label_es?: string | null
          kpi_label_pt?: string
          notes?: string | null
          organization_id?: string
          target_unit?: string
          target_value?: number
          updated_at?: string | null
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "annual_kpi_targets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_chains: {
        Row: {
          activated_at: string | null
          approved_at: string | null
          closed_at: string | null
          closed_by: string | null
          created_at: string
          document_id: string
          gates: Json
          id: string
          notes: string | null
          opened_at: string | null
          opened_by: string | null
          status: string
          updated_at: string
          version_id: string
        }
        Insert: {
          activated_at?: string | null
          approved_at?: string | null
          closed_at?: string | null
          closed_by?: string | null
          created_at?: string
          document_id: string
          gates?: Json
          id?: string
          notes?: string | null
          opened_at?: string | null
          opened_by?: string | null
          status?: string
          updated_at?: string
          version_id: string
        }
        Update: {
          activated_at?: string | null
          approved_at?: string | null
          closed_at?: string | null
          closed_by?: string | null
          created_at?: string
          document_id?: string
          gates?: Json
          id?: string
          notes?: string | null
          opened_at?: string | null
          opened_by?: string | null
          status?: string
          updated_at?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_chains_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "approval_chains_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_closed_by_fkey"
            columns: ["closed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "governance_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "approval_chains_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_chains_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      approval_signoffs: {
        Row: {
          approval_chain_id: string
          comment_body: string | null
          content_snapshot: Json
          created_at: string
          gate_kind: string
          id: string
          referenced_policy_version_id: string | null
          sections_verified: Json | null
          signature_hash: string
          signed_at: string
          signed_ip: unknown
          signed_user_agent: string | null
          signer_id: string
          signoff_type: string
        }
        Insert: {
          approval_chain_id: string
          comment_body?: string | null
          content_snapshot: Json
          created_at?: string
          gate_kind: string
          id?: string
          referenced_policy_version_id?: string | null
          sections_verified?: Json | null
          signature_hash: string
          signed_at?: string
          signed_ip?: unknown
          signed_user_agent?: string | null
          signer_id: string
          signoff_type: string
        }
        Update: {
          approval_chain_id?: string
          comment_body?: string | null
          content_snapshot?: Json
          created_at?: string
          gate_kind?: string
          id?: string
          referenced_policy_version_id?: string | null
          sections_verified?: Json | null
          signature_hash?: string
          signed_at?: string
          signed_ip?: unknown
          signed_user_agent?: string | null
          signer_id?: string
          signoff_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "approval_signoffs_approval_chain_id_fkey"
            columns: ["approval_chain_id"]
            isOneToOne: false
            referencedRelation: "approval_chains"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_signoffs_referenced_policy_version_id_fkey"
            columns: ["referenced_policy_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_signoffs_signer_id_fkey"
            columns: ["signer_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_signoffs_signer_id_fkey"
            columns: ["signer_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "approval_signoffs_signer_id_fkey"
            columns: ["signer_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_signoffs_signer_id_fkey"
            columns: ["signer_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "approval_signoffs_signer_id_fkey"
            columns: ["signer_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      artia_discovery_dumps: {
        Row: {
          account_id: number
          dump_kind: string
          dumped_at: string
          id: string
          notes: string | null
          payload: Json
          project_id: number | null
          project_name: string | null
          source_query: string | null
        }
        Insert: {
          account_id: number
          dump_kind: string
          dumped_at?: string
          id?: string
          notes?: string | null
          payload: Json
          project_id?: number | null
          project_name?: string | null
          source_query?: string | null
        }
        Update: {
          account_id?: number
          dump_kind?: string
          dumped_at?: string
          id?: string
          notes?: string | null
          payload?: Json
          project_id?: number | null
          project_name?: string | null
          source_query?: string | null
        }
        Relationships: []
      }
      artia_status_reports: {
        Row: {
          artia_activity_id: number | null
          artia_synced_at: string | null
          body_md: string
          cycle_year: number
          generated_at: string
          generated_by_cron: boolean | null
          id: string
          metrics_json: Json
          report_month: string
        }
        Insert: {
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          body_md: string
          cycle_year: number
          generated_at?: string
          generated_by_cron?: boolean | null
          id?: string
          metrics_json?: Json
          report_month: string
        }
        Update: {
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          body_md?: string
          cycle_year?: number
          generated_at?: string
          generated_by_cron?: boolean | null
          id?: string
          metrics_json?: Json
          report_month?: string
        }
        Relationships: []
      }
      attendance: {
        Row: {
          checked_in_at: string | null
          corrected_by: string | null
          created_at: string | null
          edited_at: string | null
          edited_by: string | null
          event_id: string
          excuse_reason: string | null
          excused: boolean | null
          id: string
          marked_by: string | null
          member_id: string
          notes: string | null
          organization_id: string
          present: boolean
          registered_by: string | null
          updated_at: string | null
        }
        Insert: {
          checked_in_at?: string | null
          corrected_by?: string | null
          created_at?: string | null
          edited_at?: string | null
          edited_by?: string | null
          event_id: string
          excuse_reason?: string | null
          excused?: boolean | null
          id?: string
          marked_by?: string | null
          member_id: string
          notes?: string | null
          organization_id?: string
          present?: boolean
          registered_by?: string | null
          updated_at?: string | null
        }
        Update: {
          checked_in_at?: string | null
          corrected_by?: string | null
          created_at?: string | null
          edited_at?: string | null
          edited_by?: string | null
          event_id?: string
          excuse_reason?: string | null
          excused?: boolean | null
          id?: string
          marked_by?: string | null
          member_id?: string
          notes?: string | null
          organization_id?: string
          present?: boolean
          registered_by?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_corrected_by_fkey"
            columns: ["corrected_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      blog_likes: {
        Row: {
          created_at: string | null
          id: string
          member_id: string
          post_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          member_id: string
          post_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          member_id?: string
          post_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "blog_likes_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_likes_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "blog_likes_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_likes_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_likes_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "blog_posts"
            referencedColumns: ["id"]
          },
        ]
      }
      blog_posts: {
        Row: {
          author_member_id: string | null
          body_html: Json
          category: string | null
          cover_image_url: string | null
          created_at: string | null
          excerpt: Json
          github_repo_url: string | null
          id: string
          is_featured: boolean | null
          like_count: number | null
          organization_id: string
          published_at: string | null
          series_id: string | null
          series_position: number | null
          slug: string
          source_idea_id: string | null
          status: string | null
          tags: string[] | null
          title: Json
          updated_at: string | null
          view_count: number | null
        }
        Insert: {
          author_member_id?: string | null
          body_html: Json
          category?: string | null
          cover_image_url?: string | null
          created_at?: string | null
          excerpt: Json
          github_repo_url?: string | null
          id?: string
          is_featured?: boolean | null
          like_count?: number | null
          organization_id?: string
          published_at?: string | null
          series_id?: string | null
          series_position?: number | null
          slug: string
          source_idea_id?: string | null
          status?: string | null
          tags?: string[] | null
          title: Json
          updated_at?: string | null
          view_count?: number | null
        }
        Update: {
          author_member_id?: string | null
          body_html?: Json
          category?: string | null
          cover_image_url?: string | null
          created_at?: string | null
          excerpt?: Json
          github_repo_url?: string | null
          id?: string
          is_featured?: boolean | null
          like_count?: number | null
          organization_id?: string
          published_at?: string | null
          series_id?: string | null
          series_position?: number | null
          slug?: string
          source_idea_id?: string | null
          status?: string | null
          tags?: string[] | null
          title?: Json
          updated_at?: string | null
          view_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "blog_posts_author_member_id_fkey"
            columns: ["author_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_posts_author_member_id_fkey"
            columns: ["author_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "blog_posts_author_member_id_fkey"
            columns: ["author_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_posts_author_member_id_fkey"
            columns: ["author_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_posts_author_member_id_fkey"
            columns: ["author_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_posts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_posts_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "publication_series"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blog_posts_source_idea_id_fkey"
            columns: ["source_idea_id"]
            isOneToOne: false
            referencedRelation: "publication_ideas"
            referencedColumns: ["id"]
          },
        ]
      }
      board_drive_links: {
        Row: {
          board_id: string
          drive_folder_id: string
          drive_folder_name: string | null
          drive_folder_url: string
          id: string
          linked_at: string
          linked_by: string
          unlinked_at: string | null
          unlinked_by: string | null
        }
        Insert: {
          board_id: string
          drive_folder_id: string
          drive_folder_name?: string | null
          drive_folder_url: string
          id?: string
          linked_at?: string
          linked_by: string
          unlinked_at?: string | null
          unlinked_by?: string | null
        }
        Update: {
          board_id?: string
          drive_folder_id?: string
          drive_folder_name?: string | null
          drive_folder_url?: string
          id?: string
          linked_at?: string
          linked_by?: string
          unlinked_at?: string | null
          unlinked_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "board_drive_links_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      board_item_assignments: {
        Row: {
          assigned_at: string | null
          assigned_by: string | null
          id: string
          item_id: string
          member_id: string
          role: string
        }
        Insert: {
          assigned_at?: string | null
          assigned_by?: string | null
          id?: string
          item_id: string
          member_id: string
          role?: string
        }
        Update: {
          assigned_at?: string | null
          assigned_by?: string | null
          id?: string
          item_id?: string
          member_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_item_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_assignments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_assignments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      board_item_checklists: {
        Row: {
          assigned_at: string | null
          assigned_by: string | null
          assigned_to: string | null
          board_item_id: string
          completed_at: string | null
          completed_by: string | null
          created_at: string
          id: string
          is_completed: boolean
          position: number
          target_date: string | null
          text: string
        }
        Insert: {
          assigned_at?: string | null
          assigned_by?: string | null
          assigned_to?: string | null
          board_item_id: string
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          id?: string
          is_completed?: boolean
          position?: number
          target_date?: string | null
          text: string
        }
        Update: {
          assigned_at?: string | null
          assigned_by?: string | null
          assigned_to?: string | null
          board_item_id?: string
          completed_at?: string | null
          completed_by?: string | null
          created_at?: string
          id?: string
          is_completed?: boolean
          position?: number
          target_date?: string | null
          text?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_item_checklists_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_checklists_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_checklists_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      board_item_comments: {
        Row: {
          author_id: string
          board_item_id: string
          body: string
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          mentioned_member_ids: string[] | null
          parent_comment_id: string | null
          updated_at: string
        }
        Insert: {
          author_id: string
          board_item_id: string
          body: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          mentioned_member_ids?: string[] | null
          parent_comment_id?: string | null
          updated_at?: string
        }
        Update: {
          author_id?: string
          board_item_id?: string
          body?: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          mentioned_member_ids?: string[] | null
          parent_comment_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_item_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_comments_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_comments_parent_comment_id_fkey"
            columns: ["parent_comment_id"]
            isOneToOne: false
            referencedRelation: "board_item_comments"
            referencedColumns: ["id"]
          },
        ]
      }
      board_item_event_links: {
        Row: {
          author_id: string | null
          board_item_id: string
          created_at: string
          event_id: string
          id: string
          link_type: string
          note: string | null
          organization_id: string
        }
        Insert: {
          author_id?: string | null
          board_item_id: string
          created_at?: string
          event_id: string
          id?: string
          link_type: string
          note?: string | null
          organization_id: string
        }
        Update: {
          author_id?: string | null
          board_item_id?: string
          created_at?: string
          event_id?: string
          id?: string
          link_type?: string
          note?: string | null
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_item_event_links_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_event_links_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_event_links_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_event_links_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_event_links_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_event_links_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_event_links_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_event_links_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      board_item_files: {
        Row: {
          board_item_id: string
          created_at: string
          deleted_at: string | null
          drive_file_id: string
          drive_file_url: string
          filename: string
          id: string
          mime_type: string | null
          size_bytes: number | null
          uploaded_by: string | null
          uploaded_via: string | null
        }
        Insert: {
          board_item_id: string
          created_at?: string
          deleted_at?: string | null
          drive_file_id: string
          drive_file_url: string
          filename: string
          id?: string
          mime_type?: string | null
          size_bytes?: number | null
          uploaded_by?: string | null
          uploaded_via?: string | null
        }
        Update: {
          board_item_id?: string
          created_at?: string
          deleted_at?: string | null
          drive_file_id?: string
          drive_file_url?: string
          filename?: string
          id?: string
          mime_type?: string | null
          size_bytes?: number | null
          uploaded_by?: string | null
          uploaded_via?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "board_item_files_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_files_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_files_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_item_files_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_files_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_files_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      board_item_tag_assignments: {
        Row: {
          board_item_id: string
          created_at: string | null
          id: string
          tag_id: string
        }
        Insert: {
          board_item_id: string
          created_at?: string | null
          id?: string
          tag_id: string
        }
        Update: {
          board_item_id?: string
          created_at?: string | null
          id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_item_tag_assignments_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_item_tag_assignments_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      board_items: {
        Row: {
          actual_completion_date: string | null
          artia_activity_id: number | null
          artia_synced_at: string | null
          assignee_id: string | null
          attachments: Json | null
          baseline_date: string | null
          baseline_locked_at: string | null
          board_id: string
          checklist: Json | null
          created_at: string
          created_by: string | null
          curation_due_at: string | null
          curation_status: string
          cycle: number | null
          description: string | null
          due_date: string | null
          forecast_date: string | null
          id: string
          is_mirror: boolean | null
          is_portfolio_item: boolean | null
          labels: Json | null
          leader_review_completed_at: string | null
          leader_review_decision: string | null
          leader_review_notes: string | null
          leader_reviewer_id: string | null
          mirror_source_id: string | null
          mirror_target_id: string | null
          organization_id: string
          peer_review_completed_at: string | null
          peer_review_summary: string | null
          peer_review_waived: boolean
          peer_review_waived_reason: string | null
          portfolio_kpi_refs: string[] | null
          position: number
          reviewer_id: string | null
          source_board: string | null
          source_card_id: string | null
          source_partner_id: string | null
          source_type: string | null
          status: string
          tags: string[] | null
          title: string
          updated_at: string
        }
        Insert: {
          actual_completion_date?: string | null
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          assignee_id?: string | null
          attachments?: Json | null
          baseline_date?: string | null
          baseline_locked_at?: string | null
          board_id: string
          checklist?: Json | null
          created_at?: string
          created_by?: string | null
          curation_due_at?: string | null
          curation_status?: string
          cycle?: number | null
          description?: string | null
          due_date?: string | null
          forecast_date?: string | null
          id?: string
          is_mirror?: boolean | null
          is_portfolio_item?: boolean | null
          labels?: Json | null
          leader_review_completed_at?: string | null
          leader_review_decision?: string | null
          leader_review_notes?: string | null
          leader_reviewer_id?: string | null
          mirror_source_id?: string | null
          mirror_target_id?: string | null
          organization_id?: string
          peer_review_completed_at?: string | null
          peer_review_summary?: string | null
          peer_review_waived?: boolean
          peer_review_waived_reason?: string | null
          portfolio_kpi_refs?: string[] | null
          position?: number
          reviewer_id?: string | null
          source_board?: string | null
          source_card_id?: string | null
          source_partner_id?: string | null
          source_type?: string | null
          status?: string
          tags?: string[] | null
          title: string
          updated_at?: string
        }
        Update: {
          actual_completion_date?: string | null
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          assignee_id?: string | null
          attachments?: Json | null
          baseline_date?: string | null
          baseline_locked_at?: string | null
          board_id?: string
          checklist?: Json | null
          created_at?: string
          created_by?: string | null
          curation_due_at?: string | null
          curation_status?: string
          cycle?: number | null
          description?: string | null
          due_date?: string | null
          forecast_date?: string | null
          id?: string
          is_mirror?: boolean | null
          is_portfolio_item?: boolean | null
          labels?: Json | null
          leader_review_completed_at?: string | null
          leader_review_decision?: string | null
          leader_review_notes?: string | null
          leader_reviewer_id?: string | null
          mirror_source_id?: string | null
          mirror_target_id?: string | null
          organization_id?: string
          peer_review_completed_at?: string | null
          peer_review_summary?: string | null
          peer_review_waived?: boolean
          peer_review_waived_reason?: string | null
          portfolio_kpi_refs?: string[] | null
          position?: number
          reviewer_id?: string | null
          source_board?: string | null
          source_card_id?: string | null
          source_partner_id?: string | null
          source_type?: string | null
          status?: string
          tags?: string[] | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_leader_reviewer_id_fkey"
            columns: ["leader_reviewer_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_leader_reviewer_id_fkey"
            columns: ["leader_reviewer_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_leader_reviewer_id_fkey"
            columns: ["leader_reviewer_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_leader_reviewer_id_fkey"
            columns: ["leader_reviewer_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_leader_reviewer_id_fkey"
            columns: ["leader_reviewer_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_mirror_source_id_fkey"
            columns: ["mirror_source_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_mirror_target_id_fkey"
            columns: ["mirror_target_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_items_source_partner_id_fkey"
            columns: ["source_partner_id"]
            isOneToOne: false
            referencedRelation: "partner_entities"
            referencedColumns: ["id"]
          },
        ]
      }
      board_lifecycle_events: {
        Row: {
          action: string
          actor_member_id: string | null
          board_id: string | null
          created_at: string
          id: number
          item_id: string | null
          new_status: string | null
          organization_id: string
          previous_status: string | null
          reason: string | null
          review_round: number | null
          review_score: Json | null
          sla_deadline: string | null
        }
        Insert: {
          action: string
          actor_member_id?: string | null
          board_id?: string | null
          created_at?: string
          id?: number
          item_id?: string | null
          new_status?: string | null
          organization_id?: string
          previous_status?: string | null
          reason?: string | null
          review_round?: number | null
          review_score?: Json | null
          sla_deadline?: string | null
        }
        Update: {
          action?: string
          actor_member_id?: string | null
          board_id?: string | null
          created_at?: string
          id?: number
          item_id?: string | null
          new_status?: string | null
          organization_id?: string
          previous_status?: string | null
          reason?: string | null
          review_round?: number | null
          review_score?: Json | null
          sla_deadline?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_lifecycle_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      board_members: {
        Row: {
          board_id: string
          board_role: string
          granted_at: string | null
          granted_by: string | null
          id: string
          member_id: string
        }
        Insert: {
          board_id: string
          board_role?: string
          granted_at?: string | null
          granted_by?: string | null
          id?: string
          member_id: string
        }
        Update: {
          board_id?: string
          board_role?: string
          granted_at?: string | null
          granted_by?: string | null
          id?: string
          member_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_members_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_members_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "board_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      board_sla_config: {
        Row: {
          board_id: string
          created_at: string | null
          curation_pipeline: Json | null
          id: string
          max_review_rounds: number
          organization_id: string
          reviewers_required: number
          rubric_criteria: Json
          sla_days: number
          updated_at: string | null
        }
        Insert: {
          board_id: string
          created_at?: string | null
          curation_pipeline?: Json | null
          id?: string
          max_review_rounds?: number
          organization_id?: string
          reviewers_required?: number
          rubric_criteria?: Json
          sla_days?: number
          updated_at?: string | null
        }
        Update: {
          board_id?: string
          created_at?: string | null
          curation_pipeline?: Json | null
          id?: string
          max_review_rounds?: number
          organization_id?: string
          reviewers_required?: number
          rubric_criteria?: Json
          sla_days?: number
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "board_sla_config_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: true
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "board_sla_config_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      board_source_tribe_map: {
        Row: {
          is_active: boolean
          notes: string | null
          source_board: string
          tribe_id: number
          updated_at: string
        }
        Insert: {
          is_active?: boolean
          notes?: string | null
          source_board: string
          tribe_id: number
          updated_at?: string
        }
        Update: {
          is_active?: boolean
          notes?: string | null
          source_board?: string
          tribe_id?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_source_tribe_map_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      board_taxonomy_alerts: {
        Row: {
          alert_code: string
          board_id: string | null
          created_at: string
          id: number
          payload: Json
          resolved_at: string | null
          severity: string
        }
        Insert: {
          alert_code: string
          board_id?: string | null
          created_at?: string
          id?: never
          payload?: Json
          resolved_at?: string | null
          severity?: string
        }
        Update: {
          alert_code?: string
          board_id?: string | null
          created_at?: string
          id?: never
          payload?: Json
          resolved_at?: string | null
          severity?: string
        }
        Relationships: [
          {
            foreignKeyName: "board_taxonomy_alerts_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
        ]
      }
      broadcast_log: {
        Row: {
          body: string
          error_detail: string | null
          id: string
          initiative_id: string | null
          recipient_count: number
          sender_id: string
          sent_at: string
          status: string
          subject: string
        }
        Insert: {
          body: string
          error_detail?: string | null
          id?: string
          initiative_id?: string | null
          recipient_count?: number
          sender_id: string
          sent_at?: string
          status?: string
          subject: string
        }
        Update: {
          body?: string
          error_detail?: string | null
          id?: string
          initiative_id?: string | null
          recipient_count?: number
          sender_id?: string
          sent_at?: string
          status?: string
          subject?: string
        }
        Relationships: [
          {
            foreignKeyName: "broadcast_log_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "broadcast_log_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      campaign_recipients: {
        Row: {
          bot_suspected: boolean | null
          bounce_type: string | null
          bounced_at: string | null
          click_count: number | null
          clicked_at: string | null
          complained_at: string | null
          created_at: string | null
          delivered: boolean | null
          delivered_at: string | null
          error_message: string | null
          external_email: string | null
          external_name: string | null
          first_opened_at: string | null
          id: string
          language: string | null
          last_user_agent: string | null
          member_id: string | null
          open_count: number | null
          opened: boolean | null
          opened_at: string | null
          resend_id: string | null
          send_id: string
          status: string | null
          unsubscribe_token: string | null
          unsubscribed: boolean | null
        }
        Insert: {
          bot_suspected?: boolean | null
          bounce_type?: string | null
          bounced_at?: string | null
          click_count?: number | null
          clicked_at?: string | null
          complained_at?: string | null
          created_at?: string | null
          delivered?: boolean | null
          delivered_at?: string | null
          error_message?: string | null
          external_email?: string | null
          external_name?: string | null
          first_opened_at?: string | null
          id?: string
          language?: string | null
          last_user_agent?: string | null
          member_id?: string | null
          open_count?: number | null
          opened?: boolean | null
          opened_at?: string | null
          resend_id?: string | null
          send_id: string
          status?: string | null
          unsubscribe_token?: string | null
          unsubscribed?: boolean | null
        }
        Update: {
          bot_suspected?: boolean | null
          bounce_type?: string | null
          bounced_at?: string | null
          click_count?: number | null
          clicked_at?: string | null
          complained_at?: string | null
          created_at?: string | null
          delivered?: boolean | null
          delivered_at?: string | null
          error_message?: string | null
          external_email?: string | null
          external_name?: string | null
          first_opened_at?: string | null
          id?: string
          language?: string | null
          last_user_agent?: string | null
          member_id?: string | null
          open_count?: number | null
          opened?: boolean | null
          opened_at?: string | null
          resend_id?: string | null
          send_id?: string
          status?: string | null
          unsubscribe_token?: string | null
          unsubscribed?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "campaign_recipients_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_recipients_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "campaign_recipients_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_recipients_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_recipients_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_recipients_send_id_fkey"
            columns: ["send_id"]
            isOneToOne: false
            referencedRelation: "campaign_sends"
            referencedColumns: ["id"]
          },
        ]
      }
      campaign_sends: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          audience_filter: Json
          created_at: string | null
          delivered_count: number | null
          error_log: string | null
          failed_count: number | null
          id: string
          recipient_count: number
          scheduled_at: string | null
          sent_at: string | null
          sent_by: string
          source_idea_id: string | null
          status: string | null
          template_id: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          audience_filter: Json
          created_at?: string | null
          delivered_count?: number | null
          error_log?: string | null
          failed_count?: number | null
          id?: string
          recipient_count?: number
          scheduled_at?: string | null
          sent_at?: string | null
          sent_by: string
          source_idea_id?: string | null
          status?: string | null
          template_id: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          audience_filter?: Json
          created_at?: string | null
          delivered_count?: number | null
          error_log?: string | null
          failed_count?: number | null
          id?: string
          recipient_count?: number
          scheduled_at?: string | null
          sent_at?: string | null
          sent_by?: string
          source_idea_id?: string | null
          status?: string | null
          template_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "campaign_sends_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "campaign_sends_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_sent_by_fkey"
            columns: ["sent_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_sent_by_fkey"
            columns: ["sent_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "campaign_sends_sent_by_fkey"
            columns: ["sent_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_sent_by_fkey"
            columns: ["sent_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_sent_by_fkey"
            columns: ["sent_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_source_idea_id_fkey"
            columns: ["source_idea_id"]
            isOneToOne: false
            referencedRelation: "publication_ideas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_sends_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "campaign_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      campaign_templates: {
        Row: {
          body_html: Json
          body_text: Json
          category: string
          created_at: string | null
          created_by: string | null
          id: string
          name: string
          slug: string
          source_idea_id: string | null
          subject: Json
          target_audience: Json
          updated_at: string | null
          variables: Json | null
        }
        Insert: {
          body_html: Json
          body_text: Json
          category?: string
          created_at?: string | null
          created_by?: string | null
          id?: string
          name: string
          slug: string
          source_idea_id?: string | null
          subject: Json
          target_audience?: Json
          updated_at?: string | null
          variables?: Json | null
        }
        Update: {
          body_html?: Json
          body_text?: Json
          category?: string
          created_at?: string | null
          created_by?: string | null
          id?: string
          name?: string
          slug?: string
          source_idea_id?: string | null
          subject?: Json
          target_audience?: Json
          updated_at?: string | null
          variables?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "campaign_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "campaign_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "campaign_templates_source_idea_id_fkey"
            columns: ["source_idea_id"]
            isOneToOne: false
            referencedRelation: "publication_ideas"
            referencedColumns: ["id"]
          },
        ]
      }
      certificates: {
        Row: {
          content_snapshot: Json | null
          counter_signature_hash: string | null
          counter_signed_at: string | null
          counter_signed_by: string | null
          cycle: number | null
          description: string | null
          downloaded_at: string | null
          function_role: string | null
          id: string
          issued_at: string | null
          issued_by: string | null
          language: string | null
          member_id: string
          pdf_url: string | null
          period_end: string | null
          period_start: string | null
          revoked_at: string | null
          revoked_by: string | null
          revoked_reason: string | null
          signature_hash: string | null
          signed_ip: unknown
          signed_user_agent: string | null
          source: string
          status: string | null
          template_id: string | null
          title: string
          type: string
          updated_at: string | null
          verification_code: string | null
        }
        Insert: {
          content_snapshot?: Json | null
          counter_signature_hash?: string | null
          counter_signed_at?: string | null
          counter_signed_by?: string | null
          cycle?: number | null
          description?: string | null
          downloaded_at?: string | null
          function_role?: string | null
          id?: string
          issued_at?: string | null
          issued_by?: string | null
          language?: string | null
          member_id: string
          pdf_url?: string | null
          period_end?: string | null
          period_start?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          revoked_reason?: string | null
          signature_hash?: string | null
          signed_ip?: unknown
          signed_user_agent?: string | null
          source?: string
          status?: string | null
          template_id?: string | null
          title: string
          type: string
          updated_at?: string | null
          verification_code?: string | null
        }
        Update: {
          content_snapshot?: Json | null
          counter_signature_hash?: string | null
          counter_signed_at?: string | null
          counter_signed_by?: string | null
          cycle?: number | null
          description?: string | null
          downloaded_at?: string | null
          function_role?: string | null
          id?: string
          issued_at?: string | null
          issued_by?: string | null
          language?: string | null
          member_id?: string
          pdf_url?: string | null
          period_end?: string | null
          period_start?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          revoked_reason?: string | null
          signature_hash?: string | null
          signed_ip?: unknown
          signed_user_agent?: string | null
          source?: string
          status?: string | null
          template_id?: string | null
          title?: string
          type?: string
          updated_at?: string | null
          verification_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "certificates_counter_signed_by_fkey"
            columns: ["counter_signed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_counter_signed_by_fkey"
            columns: ["counter_signed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "certificates_counter_signed_by_fkey"
            columns: ["counter_signed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_counter_signed_by_fkey"
            columns: ["counter_signed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_counter_signed_by_fkey"
            columns: ["counter_signed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "certificates_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      champion_criteria_catalog: {
        Row: {
          active: boolean
          created_at: string
          description_i18n: Json | null
          display_name_i18n: Json
          id: string
          organization_id: string
          slug: string
          sort_order: number
          surface: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          description_i18n?: Json | null
          display_name_i18n: Json
          id?: string
          organization_id: string
          slug: string
          sort_order?: number
          surface: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          description_i18n?: Json | null
          display_name_i18n?: Json
          id?: string
          organization_id?: string
          slug?: string
          sort_order?: number
          surface?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "champion_criteria_catalog_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      champions_awarded: {
        Row: {
          awarded_by: string
          context_id: string
          context_kind: string
          created_at: string
          criteria_met: string[]
          id: string
          initiative_id: string | null
          justification: string
          organization_id: string
          points_awarded: number
          recipient_id: string
          revoked_at: string | null
          revoked_by: string | null
          revoked_reason: string | null
          status: string
          surface: string
          updated_at: string
        }
        Insert: {
          awarded_by: string
          context_id: string
          context_kind: string
          created_at?: string
          criteria_met: string[]
          id?: string
          initiative_id?: string | null
          justification: string
          organization_id: string
          points_awarded: number
          recipient_id: string
          revoked_at?: string | null
          revoked_by?: string | null
          revoked_reason?: string | null
          status?: string
          surface: string
          updated_at?: string
        }
        Update: {
          awarded_by?: string
          context_id?: string
          context_kind?: string
          created_at?: string
          criteria_met?: string[]
          id?: string
          initiative_id?: string | null
          justification?: string
          organization_id?: string
          points_awarded?: number
          recipient_id?: string
          revoked_at?: string | null
          revoked_by?: string | null
          revoked_reason?: string | null
          status?: string
          surface?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "champions_awarded_awarded_by_fkey"
            columns: ["awarded_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_awarded_by_fkey"
            columns: ["awarded_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "champions_awarded_awarded_by_fkey"
            columns: ["awarded_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_awarded_by_fkey"
            columns: ["awarded_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_awarded_by_fkey"
            columns: ["awarded_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "champions_awarded_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "champions_awarded_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "champions_awarded_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      change_requests: {
        Row: {
          approved_at: string | null
          approved_by_members: string[] | null
          auto_generated: boolean | null
          category: string | null
          cr_number: string
          cr_type: string | null
          created_at: string | null
          description: string | null
          gc_references: string[] | null
          id: string
          impact_description: string | null
          impact_level: string | null
          implemented_at: string | null
          implemented_by: string | null
          justification: string | null
          manual_section_ids: string[] | null
          manual_version_from: string | null
          manual_version_to: string | null
          organization_id: string
          priority: string | null
          proposed_changes: string | null
          requested_by: string | null
          requested_by_role: string | null
          review_notes: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          source_document_id: string | null
          status: string | null
          submitted_at: string | null
          title: string
          updated_at: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by_members?: string[] | null
          auto_generated?: boolean | null
          category?: string | null
          cr_number: string
          cr_type?: string | null
          created_at?: string | null
          description?: string | null
          gc_references?: string[] | null
          id?: string
          impact_description?: string | null
          impact_level?: string | null
          implemented_at?: string | null
          implemented_by?: string | null
          justification?: string | null
          manual_section_ids?: string[] | null
          manual_version_from?: string | null
          manual_version_to?: string | null
          organization_id?: string
          priority?: string | null
          proposed_changes?: string | null
          requested_by?: string | null
          requested_by_role?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_document_id?: string | null
          status?: string | null
          submitted_at?: string | null
          title: string
          updated_at?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by_members?: string[] | null
          auto_generated?: boolean | null
          category?: string | null
          cr_number?: string
          cr_type?: string | null
          created_at?: string | null
          description?: string | null
          gc_references?: string[] | null
          id?: string
          impact_description?: string | null
          impact_level?: string | null
          implemented_at?: string | null
          implemented_by?: string | null
          justification?: string | null
          manual_section_ids?: string[] | null
          manual_version_from?: string | null
          manual_version_to?: string | null
          organization_id?: string
          priority?: string | null
          proposed_changes?: string | null
          requested_by?: string | null
          requested_by_role?: string | null
          review_notes?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          source_document_id?: string | null
          status?: string | null
          submitted_at?: string | null
          title?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "change_requests_implemented_by_fkey"
            columns: ["implemented_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_implemented_by_fkey"
            columns: ["implemented_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "change_requests_implemented_by_fkey"
            columns: ["implemented_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_implemented_by_fkey"
            columns: ["implemented_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_implemented_by_fkey"
            columns: ["implemented_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_requested_by_fkey"
            columns: ["requested_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "change_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "change_requests_source_document_id_fkey"
            columns: ["source_document_id"]
            isOneToOne: false
            referencedRelation: "governance_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      chapter_needs: {
        Row: {
          admin_notes: string | null
          category: string
          chapter: string
          created_at: string
          description: string | null
          id: string
          status: string
          submitted_by: string
          title: string
          updated_at: string
        }
        Insert: {
          admin_notes?: string | null
          category: string
          chapter: string
          created_at?: string
          description?: string | null
          id?: string
          status?: string
          submitted_by: string
          title: string
          updated_at?: string
        }
        Update: {
          admin_notes?: string | null
          category?: string
          chapter?: string
          created_at?: string
          description?: string | null
          id?: string
          status?: string
          submitted_by?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "chapter_needs_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_needs_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "chapter_needs_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_needs_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_needs_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      chapter_registry: {
        Row: {
          chapter_code: string
          cnpj: string | null
          country: string
          created_at: string | null
          display_order: number | null
          id: string
          is_active: boolean | null
          is_contracting_chapter: boolean | null
          legal_name: string
          logo_url: string | null
          state: string
          updated_at: string | null
        }
        Insert: {
          chapter_code: string
          cnpj?: string | null
          country?: string
          created_at?: string | null
          display_order?: number | null
          id?: string
          is_active?: boolean | null
          is_contracting_chapter?: boolean | null
          legal_name: string
          logo_url?: string | null
          state: string
          updated_at?: string | null
        }
        Update: {
          chapter_code?: string
          cnpj?: string | null
          country?: string
          created_at?: string | null
          display_order?: number | null
          id?: string
          is_active?: boolean | null
          is_contracting_chapter?: boolean | null
          legal_name?: string
          logo_url?: string | null
          state?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      chapters: {
        Row: {
          code: string
          created_at: string
          id: string
          name: string
          organization_id: string
          pmi_chapter_code: string | null
          region: string | null
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          name: string
          organization_id: string
          pmi_chapter_code?: string | null
          region?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          pmi_chapter_code?: string | null
          region?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "chapters_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      comms_channel_config: {
        Row: {
          api_key: string | null
          channel: string
          config: Json | null
          created_at: string | null
          id: string
          last_sync_at: string | null
          oauth_refresh_token: string | null
          oauth_token: string | null
          organization_id: string
          sync_status: string | null
          token_expires_at: string | null
          updated_at: string | null
        }
        Insert: {
          api_key?: string | null
          channel: string
          config?: Json | null
          created_at?: string | null
          id?: string
          last_sync_at?: string | null
          oauth_refresh_token?: string | null
          oauth_token?: string | null
          organization_id?: string
          sync_status?: string | null
          token_expires_at?: string | null
          updated_at?: string | null
        }
        Update: {
          api_key?: string | null
          channel?: string
          config?: Json | null
          created_at?: string | null
          id?: string
          last_sync_at?: string | null
          oauth_refresh_token?: string | null
          oauth_token?: string | null
          organization_id?: string
          sync_status?: string | null
          token_expires_at?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "comms_channel_config_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      comms_media_items: {
        Row: {
          caption: string | null
          channel: string
          comments: number | null
          external_id: string
          id: string
          likes: number | null
          media_type: string | null
          payload: Json | null
          permalink: string | null
          published_at: string | null
          reach: number | null
          saves: number | null
          shares: number | null
          synced_at: string | null
          thumbnail_url: string | null
          views: number | null
        }
        Insert: {
          caption?: string | null
          channel: string
          comments?: number | null
          external_id: string
          id?: string
          likes?: number | null
          media_type?: string | null
          payload?: Json | null
          permalink?: string | null
          published_at?: string | null
          reach?: number | null
          saves?: number | null
          shares?: number | null
          synced_at?: string | null
          thumbnail_url?: string | null
          views?: number | null
        }
        Update: {
          caption?: string | null
          channel?: string
          comments?: number | null
          external_id?: string
          id?: string
          likes?: number | null
          media_type?: string | null
          payload?: Json | null
          permalink?: string | null
          published_at?: string | null
          reach?: number | null
          saves?: number | null
          shares?: number | null
          synced_at?: string | null
          thumbnail_url?: string | null
          views?: number | null
        }
        Relationships: []
      }
      comms_metrics_daily: {
        Row: {
          audience: number | null
          channel: string
          created_at: string
          created_by: string | null
          engagement_rate: number | null
          id: number
          leads: number | null
          metric_date: string
          payload: Json
          publish_batch_id: string | null
          published_at: string | null
          published_by: string | null
          reach: number | null
          source: string
          updated_at: string
        }
        Insert: {
          audience?: number | null
          channel: string
          created_at?: string
          created_by?: string | null
          engagement_rate?: number | null
          id?: number
          leads?: number | null
          metric_date: string
          payload?: Json
          publish_batch_id?: string | null
          published_at?: string | null
          published_by?: string | null
          reach?: number | null
          source?: string
          updated_at?: string
        }
        Update: {
          audience?: number | null
          channel?: string
          created_at?: string
          created_by?: string | null
          engagement_rate?: number | null
          id?: number
          leads?: number | null
          metric_date?: string
          payload?: Json
          publish_batch_id?: string | null
          published_at?: string | null
          published_by?: string | null
          reach?: number | null
          source?: string
          updated_at?: string
        }
        Relationships: []
      }
      comms_metrics_ingestion_log: {
        Row: {
          context: Json
          created_at: string
          error_message: string | null
          fetched_rows: number
          finished_at: string | null
          id: number
          invalid_rows: number
          run_key: string
          source: string
          status: string
          triggered_by: string
          upserted_rows: number
        }
        Insert: {
          context?: Json
          created_at?: string
          error_message?: string | null
          fetched_rows?: number
          finished_at?: string | null
          id?: number
          invalid_rows?: number
          run_key: string
          source: string
          status: string
          triggered_by?: string
          upserted_rows?: number
        }
        Update: {
          context?: Json
          created_at?: string
          error_message?: string | null
          fetched_rows?: number
          finished_at?: string | null
          id?: number
          invalid_rows?: number
          run_key?: string
          source?: string
          status?: string
          triggered_by?: string
          upserted_rows?: number
        }
        Relationships: []
      }
      comms_token_alerts: {
        Row: {
          acknowledged: boolean | null
          acknowledged_by: string | null
          alert_type: string
          channel: string
          created_at: string | null
          days_until_expiry: number | null
          id: string
          message: string
        }
        Insert: {
          acknowledged?: boolean | null
          acknowledged_by?: string | null
          alert_type: string
          channel: string
          created_at?: string | null
          days_until_expiry?: number | null
          id?: string
          message: string
        }
        Update: {
          acknowledged?: boolean | null
          acknowledged_by?: string | null
          alert_type?: string
          channel?: string
          created_at?: string | null
          days_until_expiry?: number | null
          id?: string
          message?: string
        }
        Relationships: [
          {
            foreignKeyName: "comms_token_alerts_channel_fkey"
            columns: ["channel"]
            isOneToOne: false
            referencedRelation: "comms_channel_config"
            referencedColumns: ["channel"]
          },
        ]
      }
      communication_templates: {
        Row: {
          body_html_tpl: string
          created_at: string
          id: number
          is_active: boolean
          label: string
          signature_tpl: string
          slug: string
          subject_tpl: string
          updated_at: string
          variables: string[]
        }
        Insert: {
          body_html_tpl?: string
          created_at?: string
          id?: number
          is_active?: boolean
          label: string
          signature_tpl?: string
          slug: string
          subject_tpl?: string
          updated_at?: string
          variables?: string[]
        }
        Update: {
          body_html_tpl?: string
          created_at?: string
          id?: number
          is_active?: boolean
          label?: string
          signature_tpl?: string
          slug?: string
          subject_tpl?: string
          updated_at?: string
          variables?: string[]
        }
        Relationships: []
      }
      comparison_results: {
        Row: {
          baseline_project_id: string | null
          created_at: string | null
          id: string
          results: Json | null
          update_project_id: string | null
          user_id: string | null
        }
        Insert: {
          baseline_project_id?: string | null
          created_at?: string | null
          id?: string
          results?: Json | null
          update_project_id?: string | null
          user_id?: string | null
        }
        Update: {
          baseline_project_id?: string | null
          created_at?: string | null
          id?: string
          results?: Json | null
          update_project_id?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      consent_records: {
        Row: {
          accepted_at: string
          application_id: string | null
          channel: string
          created_at: string
          email_hash: string | null
          id: string
          ip_hash: string | null
          member_id: string | null
          organization_id: string
          policy_document_id: string | null
          policy_type: string
          policy_version: string
          revocation_reason: string | null
          revoked_at: string | null
          user_agent_hash: string | null
        }
        Insert: {
          accepted_at?: string
          application_id?: string | null
          channel: string
          created_at?: string
          email_hash?: string | null
          id?: string
          ip_hash?: string | null
          member_id?: string | null
          organization_id?: string
          policy_document_id?: string | null
          policy_type: string
          policy_version: string
          revocation_reason?: string | null
          revoked_at?: string | null
          user_agent_hash?: string | null
        }
        Update: {
          accepted_at?: string
          application_id?: string | null
          channel?: string
          created_at?: string
          email_hash?: string | null
          id?: string
          ip_hash?: string | null
          member_id?: string | null
          organization_id?: string
          policy_document_id?: string | null
          policy_type?: string
          policy_version?: string
          revocation_reason?: string | null
          revoked_at?: string | null
          user_agent_hash?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "consent_records_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "consent_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "consent_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "consent_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "consent_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "consent_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "consent_records_policy_document_id_fkey"
            columns: ["policy_document_id"]
            isOneToOne: false
            referencedRelation: "governance_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      cost_categories: {
        Row: {
          created_at: string | null
          description: string | null
          display_order: number | null
          id: string
          name: string
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          id?: string
          name: string
        }
        Update: {
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          id?: string
          name?: string
        }
        Relationships: []
      }
      cost_entries: {
        Row: {
          amount_brl: number
          category_id: string
          created_at: string | null
          created_by: string | null
          date: string
          description: string
          event_id: string | null
          id: string
          notes: string | null
          organization_id: string | null
          paid_by: string
          submission_id: string | null
          updated_at: string | null
        }
        Insert: {
          amount_brl: number
          category_id: string
          created_at?: string | null
          created_by?: string | null
          date: string
          description: string
          event_id?: string | null
          id?: string
          notes?: string | null
          organization_id?: string | null
          paid_by?: string
          submission_id?: string | null
          updated_at?: string | null
        }
        Update: {
          amount_brl?: number
          category_id?: string
          created_at?: string | null
          created_by?: string | null
          date?: string
          description?: string
          event_id?: string | null
          id?: string
          notes?: string | null
          organization_id?: string | null
          paid_by?: string
          submission_id?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cost_entries_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "cost_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "cost_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_entries_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_entries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cost_entries_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "publication_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      course_progress: {
        Row: {
          completed_at: string | null
          course_id: number | null
          id: string
          member_id: string | null
          status: string | null
          updated_at: string | null
        }
        Insert: {
          completed_at?: string | null
          course_id?: number | null
          id?: string
          member_id?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          completed_at?: string | null
          course_id?: number | null
          id?: string
          member_id?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "course_progress_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "course_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      courses: {
        Row: {
          category: string | null
          code: string
          credly_badge_name: string | null
          id: number
          is_free: boolean | null
          is_trail: boolean | null
          name: string
          organization_id: string
          sort_order: number | null
          tier: string
          url: string | null
        }
        Insert: {
          category?: string | null
          code: string
          credly_badge_name?: string | null
          id?: number
          is_free?: boolean | null
          is_trail?: boolean | null
          name: string
          organization_id?: string
          sort_order?: number | null
          tier: string
          url?: string | null
        }
        Update: {
          category?: string | null
          code?: string
          credly_badge_name?: string | null
          id?: number
          is_free?: boolean | null
          is_trail?: boolean | null
          name?: string
          organization_id?: string
          sort_order?: number | null
          tier?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "courses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      cr_approvals: {
        Row: {
          action: string
          comment: string | null
          cr_id: string
          created_at: string
          id: string
          member_id: string
          signature_hash: string
          signed_ip: unknown
          signed_user_agent: string | null
        }
        Insert: {
          action: string
          comment?: string | null
          cr_id: string
          created_at?: string
          id?: string
          member_id: string
          signature_hash: string
          signed_ip?: unknown
          signed_user_agent?: string | null
        }
        Update: {
          action?: string
          comment?: string | null
          cr_id?: string
          created_at?: string
          id?: string
          member_id?: string
          signature_hash?: string
          signed_ip?: unknown
          signed_user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cr_approvals_cr_id_fkey"
            columns: ["cr_id"]
            isOneToOne: false
            referencedRelation: "change_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cr_approvals_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cr_approvals_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "cr_approvals_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cr_approvals_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cr_approvals_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      cron_run_log: {
        Row: {
          completed_at: string | null
          errors: Json
          id: string
          metrics: Json
          organization_id: string | null
          retry_of: string | null
          scheduled_for: string
          started_at: string
          status: string
          worker_name: string
        }
        Insert: {
          completed_at?: string | null
          errors?: Json
          id?: string
          metrics?: Json
          organization_id?: string | null
          retry_of?: string | null
          scheduled_for: string
          started_at?: string
          status?: string
          worker_name: string
        }
        Update: {
          completed_at?: string | null
          errors?: Json
          id?: string
          metrics?: Json
          organization_id?: string | null
          retry_of?: string | null
          scheduled_for?: string
          started_at?: string
          status?: string
          worker_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "cron_run_log_retry_of_fkey"
            columns: ["retry_of"]
            isOneToOne: false
            referencedRelation: "cron_run_log"
            referencedColumns: ["id"]
          },
        ]
      }
      curation_review_log: {
        Row: {
          board_item_id: string
          completed_at: string
          created_at: string
          criteria_scores: Json
          curator_id: string
          decision: string
          due_date: string | null
          feedback_notes: string | null
          id: string
          metadata: Json
          organization_id: string
        }
        Insert: {
          board_item_id: string
          completed_at?: string
          created_at?: string
          criteria_scores?: Json
          curator_id: string
          decision: string
          due_date?: string | null
          feedback_notes?: string | null
          id?: string
          metadata?: Json
          organization_id?: string
        }
        Update: {
          board_item_id?: string
          completed_at?: string
          created_at?: string
          criteria_scores?: Json
          curator_id?: string
          decision?: string
          due_date?: string | null
          feedback_notes?: string | null
          id?: string
          metadata?: Json
          organization_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "curation_review_log_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curation_review_log_curator_id_fkey"
            columns: ["curator_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curation_review_log_curator_id_fkey"
            columns: ["curator_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "curation_review_log_curator_id_fkey"
            columns: ["curator_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curation_review_log_curator_id_fkey"
            columns: ["curator_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curation_review_log_curator_id_fkey"
            columns: ["curator_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curation_review_log_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      cycles: {
        Row: {
          created_at: string
          cycle_abbr: string
          cycle_code: string
          cycle_color: string
          cycle_end: string | null
          cycle_label: string
          cycle_start: string
          is_current: boolean
          organization_id: string
          sort_order: number
        }
        Insert: {
          created_at?: string
          cycle_abbr: string
          cycle_code: string
          cycle_color?: string
          cycle_end?: string | null
          cycle_label: string
          cycle_start: string
          is_current?: boolean
          organization_id?: string
          sort_order?: number
        }
        Update: {
          created_at?: string
          cycle_abbr?: string
          cycle_code?: string
          cycle_color?: string
          cycle_end?: string | null
          cycle_label?: string
          cycle_start?: string
          is_current?: boolean
          organization_id?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "cycles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      data_anomaly_log: {
        Row: {
          anomaly_type: string
          auto_fixable: boolean | null
          auto_fixed: boolean | null
          context: Json | null
          description: string
          detected_at: string | null
          fixed_at: string | null
          fixed_by: string | null
          id: string
          member_id: string | null
          severity: string
        }
        Insert: {
          anomaly_type: string
          auto_fixable?: boolean | null
          auto_fixed?: boolean | null
          context?: Json | null
          description: string
          detected_at?: string | null
          fixed_at?: string | null
          fixed_by?: string | null
          id?: string
          member_id?: string | null
          severity?: string
        }
        Update: {
          anomaly_type?: string
          auto_fixable?: boolean | null
          auto_fixed?: boolean | null
          context?: Json | null
          description?: string
          detected_at?: string | null
          fixed_at?: string | null
          fixed_by?: string | null
          id?: string
          member_id?: string | null
          severity?: string
        }
        Relationships: [
          {
            foreignKeyName: "data_anomaly_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_anomaly_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "data_anomaly_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_anomaly_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_anomaly_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      data_quality_audit_snapshots: {
        Row: {
          audit_result: Json
          created_at: string
          created_by: string | null
          flag_count: number
          id: string
          issue_count: number
          run_context: string
          run_label: string | null
          source_batch_id: string | null
        }
        Insert: {
          audit_result: Json
          created_at?: string
          created_by?: string | null
          flag_count?: number
          id?: string
          issue_count?: number
          run_context?: string
          run_label?: string | null
          source_batch_id?: string | null
        }
        Update: {
          audit_result?: Json
          created_at?: string
          created_by?: string | null
          flag_count?: number
          id?: string
          issue_count?: number
          run_context?: string
          run_label?: string | null
          source_batch_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "data_quality_audit_snapshots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      data_retention_policy: {
        Row: {
          cleanup_type: string
          created_at: string | null
          description: string | null
          id: string
          is_active: boolean | null
          retention_days: number
          table_name: string
        }
        Insert: {
          cleanup_type: string
          created_at?: string | null
          description?: string | null
          id?: string
          is_active?: boolean | null
          retention_days: number
          table_name: string
        }
        Update: {
          cleanup_type?: string
          created_at?: string | null
          description?: string | null
          id?: string
          is_active?: boolean | null
          retention_days?: number
          table_name?: string
        }
        Relationships: []
      }
      document_comment_edits: {
        Row: {
          comment_id: string
          created_at: string
          edited_at: string
          edited_by: string
          id: string
          new_body: string
          previous_body: string
        }
        Insert: {
          comment_id: string
          created_at?: string
          edited_at?: string
          edited_by: string
          id?: string
          new_body: string
          previous_body: string
        }
        Update: {
          comment_id?: string
          created_at?: string
          edited_at?: string
          edited_by?: string
          id?: string
          new_body?: string
          previous_body?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_comment_edits_comment_id_fkey"
            columns: ["comment_id"]
            isOneToOne: false
            referencedRelation: "document_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comment_edits_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comment_edits_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "document_comment_edits_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comment_edits_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comment_edits_edited_by_fkey"
            columns: ["edited_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      document_comments: {
        Row: {
          author_id: string
          body: string
          clause_anchor: string | null
          created_at: string
          document_version_id: string
          id: string
          parent_id: string | null
          resolution_note: string | null
          resolved_at: string | null
          resolved_by: string | null
          updated_at: string
          visibility: string
        }
        Insert: {
          author_id: string
          body: string
          clause_anchor?: string | null
          created_at?: string
          document_version_id: string
          id?: string
          parent_id?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          updated_at?: string
          visibility?: string
        }
        Update: {
          author_id?: string
          body?: string
          clause_anchor?: string | null
          created_at?: string
          document_version_id?: string
          id?: string
          parent_id?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "document_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_document_version_id_fkey"
            columns: ["document_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "document_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "document_comments_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_comments_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      document_versions: {
        Row: {
          authored_at: string
          authored_by: string | null
          content_diff_json: Json | null
          content_html: string
          content_markdown: string | null
          created_at: string
          document_id: string
          id: string
          locked_at: string | null
          locked_by: string | null
          notes: string | null
          published_at: string | null
          published_by: string | null
          updated_at: string
          version_label: string
          version_number: number
        }
        Insert: {
          authored_at?: string
          authored_by?: string | null
          content_diff_json?: Json | null
          content_html: string
          content_markdown?: string | null
          created_at?: string
          document_id: string
          id?: string
          locked_at?: string | null
          locked_by?: string | null
          notes?: string | null
          published_at?: string | null
          published_by?: string | null
          updated_at?: string
          version_label: string
          version_number: number
        }
        Update: {
          authored_at?: string
          authored_by?: string | null
          content_diff_json?: Json | null
          content_html?: string
          content_markdown?: string | null
          created_at?: string
          document_id?: string
          id?: string
          locked_at?: string | null
          locked_by?: string | null
          notes?: string | null
          published_at?: string | null
          published_by?: string | null
          updated_at?: string
          version_label?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "document_versions_authored_by_fkey"
            columns: ["authored_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_authored_by_fkey"
            columns: ["authored_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "document_versions_authored_by_fkey"
            columns: ["authored_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_authored_by_fkey"
            columns: ["authored_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_authored_by_fkey"
            columns: ["authored_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "governance_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_locked_by_fkey"
            columns: ["locked_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_locked_by_fkey"
            columns: ["locked_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "document_versions_locked_by_fkey"
            columns: ["locked_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_locked_by_fkey"
            columns: ["locked_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_locked_by_fkey"
            columns: ["locked_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "document_versions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "document_versions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      drive_file_discoveries: {
        Row: {
          discovered_at: string
          drive_file_id: string
          drive_file_url: string
          drive_modified_at: string | null
          filename: string
          id: string
          initiative_drive_link_id: string
          match_confidence: string
          match_strategy: string
          matched_event_id: string | null
          mime_type: string | null
          promoted_at: string | null
          promoted_by: string | null
          promoted_to_minutes_url: boolean
          size_bytes: number | null
        }
        Insert: {
          discovered_at?: string
          drive_file_id: string
          drive_file_url: string
          drive_modified_at?: string | null
          filename: string
          id?: string
          initiative_drive_link_id: string
          match_confidence?: string
          match_strategy?: string
          matched_event_id?: string | null
          mime_type?: string | null
          promoted_at?: string | null
          promoted_by?: string | null
          promoted_to_minutes_url?: boolean
          size_bytes?: number | null
        }
        Update: {
          discovered_at?: string
          drive_file_id?: string
          drive_file_url?: string
          drive_modified_at?: string | null
          filename?: string
          id?: string
          initiative_drive_link_id?: string
          match_confidence?: string
          match_strategy?: string
          matched_event_id?: string | null
          mime_type?: string | null
          promoted_at?: string | null
          promoted_by?: string | null
          promoted_to_minutes_url?: boolean
          size_bytes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "drive_file_discoveries_initiative_drive_link_id_fkey"
            columns: ["initiative_drive_link_id"]
            isOneToOne: false
            referencedRelation: "initiative_drive_links"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "drive_file_discoveries_matched_event_id_fkey"
            columns: ["matched_event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "drive_file_discoveries_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "drive_file_discoveries_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "drive_file_discoveries_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "drive_file_discoveries_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "drive_file_discoveries_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      email_verification_pending: {
        Row: {
          consumed_at: string | null
          created_at: string
          dispatched_at: string | null
          expires_at: string
          id: string
          purpose: string
          requesting_member_id: string
          target_email: string
          token: string
        }
        Insert: {
          consumed_at?: string | null
          created_at?: string
          dispatched_at?: string | null
          expires_at?: string
          id?: string
          purpose?: string
          requesting_member_id: string
          target_email: string
          token: string
        }
        Update: {
          consumed_at?: string | null
          created_at?: string
          dispatched_at?: string | null
          expires_at?: string
          id?: string
          purpose?: string
          requesting_member_id?: string
          target_email?: string
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "email_verification_pending_requesting_member_id_fkey"
            columns: ["requesting_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "email_verification_pending_requesting_member_id_fkey"
            columns: ["requesting_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "email_verification_pending_requesting_member_id_fkey"
            columns: ["requesting_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "email_verification_pending_requesting_member_id_fkey"
            columns: ["requesting_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "email_verification_pending_requesting_member_id_fkey"
            columns: ["requesting_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      email_webhook_events: {
        Row: {
          created_at: string | null
          event_type: string
          id: string
          payload: Json | null
          processed: boolean | null
          recipient_email: string | null
          resend_id: string
        }
        Insert: {
          created_at?: string | null
          event_type: string
          id?: string
          payload?: Json | null
          processed?: boolean | null
          recipient_email?: string | null
          resend_id: string
        }
        Update: {
          created_at?: string | null
          event_type?: string
          id?: string
          payload?: Json | null
          processed?: boolean | null
          recipient_email?: string | null
          resend_id?: string
        }
        Relationships: []
      }
      engagement_kind_permissions: {
        Row: {
          action: string
          created_at: string
          description: string | null
          id: number
          kind: string
          organization_id: string
          role: string
          scope: string
        }
        Insert: {
          action: string
          created_at?: string
          description?: string | null
          id?: number
          kind: string
          organization_id?: string
          role: string
          scope?: string
        }
        Update: {
          action?: string
          created_at?: string
          description?: string | null
          id?: number
          kind?: string
          organization_id?: string
          role?: string
          scope?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagement_kind_permissions_kind_fkey"
            columns: ["kind"]
            isOneToOne: false
            referencedRelation: "engagement_kinds"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "engagement_kind_permissions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      engagement_kinds: {
        Row: {
          agreement_template: string | null
          anonymization_policy: string
          auto_expire_behavior: string
          created_at: string
          created_by_role: string[]
          default_duration_days: number | null
          description: string | null
          display_name: string
          initiative_kinds_allowed: string[]
          is_initiative_scoped: boolean
          legal_basis: string
          max_duration_days: number | null
          metadata_schema: Json | null
          notify_before_expiry_days: number | null
          organization_id: string
          renewable: boolean
          requires_agreement: boolean
          requires_selection: boolean
          requires_vep: boolean
          retention_days_after_end: number | null
          revocable_by_role: string[]
          slug: string
          updated_at: string
        }
        Insert: {
          agreement_template?: string | null
          anonymization_policy?: string
          auto_expire_behavior?: string
          created_at?: string
          created_by_role?: string[]
          default_duration_days?: number | null
          description?: string | null
          display_name: string
          initiative_kinds_allowed?: string[]
          is_initiative_scoped?: boolean
          legal_basis?: string
          max_duration_days?: number | null
          metadata_schema?: Json | null
          notify_before_expiry_days?: number | null
          organization_id?: string
          renewable?: boolean
          requires_agreement?: boolean
          requires_selection?: boolean
          requires_vep?: boolean
          retention_days_after_end?: number | null
          revocable_by_role?: string[]
          slug: string
          updated_at?: string
        }
        Update: {
          agreement_template?: string | null
          anonymization_policy?: string
          auto_expire_behavior?: string
          created_at?: string
          created_by_role?: string[]
          default_duration_days?: number | null
          description?: string | null
          display_name?: string
          initiative_kinds_allowed?: string[]
          is_initiative_scoped?: boolean
          legal_basis?: string
          max_duration_days?: number | null
          metadata_schema?: Json | null
          notify_before_expiry_days?: number | null
          organization_id?: string
          renewable?: boolean
          requires_agreement?: boolean
          requires_selection?: boolean
          requires_vep?: boolean
          retention_days_after_end?: number | null
          revocable_by_role?: string[]
          slug?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagement_kinds_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      engagement_seed_templates: {
        Row: {
          active: boolean
          created_at: string
          description_i18n: Json | null
          display_name_i18n: Json
          engagements: Json
          id: string
          organization_id: string | null
          slug: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          description_i18n?: Json | null
          display_name_i18n: Json
          engagements: Json
          id?: string
          organization_id?: string | null
          slug: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          description_i18n?: Json | null
          display_name_i18n?: Json
          engagements?: Json
          id?: string
          organization_id?: string | null
          slug?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagement_seed_templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      engagements: {
        Row: {
          agreement_certificate_id: string | null
          created_at: string
          end_date: string | null
          granted_at: string | null
          granted_by: string | null
          id: string
          initiative_id: string | null
          kind: string
          legal_basis: string
          metadata: Json
          organization_id: string
          person_id: string
          revoke_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          role: string
          selection_application_id: string | null
          start_date: string
          status: string
          updated_at: string
        }
        Insert: {
          agreement_certificate_id?: string | null
          created_at?: string
          end_date?: string | null
          granted_at?: string | null
          granted_by?: string | null
          id?: string
          initiative_id?: string | null
          kind: string
          legal_basis?: string
          metadata?: Json
          organization_id?: string
          person_id: string
          revoke_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          role?: string
          selection_application_id?: string | null
          start_date?: string
          status?: string
          updated_at?: string
        }
        Update: {
          agreement_certificate_id?: string | null
          created_at?: string
          end_date?: string | null
          granted_at?: string | null
          granted_by?: string | null
          id?: string
          initiative_id?: string | null
          kind?: string
          legal_basis?: string
          metadata?: Json
          organization_id?: string
          person_id?: string
          revoke_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          role?: string
          selection_application_id?: string | null
          start_date?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagements_granted_by_fkey"
            columns: ["granted_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_kind_fkey"
            columns: ["kind"]
            isOneToOne: false
            referencedRelation: "engagement_kinds"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "engagements_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_selection_application_id_fkey"
            columns: ["selection_application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      event_audience_rules: {
        Row: {
          attendance_type: string
          created_at: string | null
          event_id: string
          id: string
          target_type: string
          target_value: string | null
        }
        Insert: {
          attendance_type?: string
          created_at?: string | null
          event_id: string
          id?: string
          target_type: string
          target_value?: string | null
        }
        Update: {
          attendance_type?: string
          created_at?: string | null
          event_id?: string
          id?: string
          target_type?: string
          target_value?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_audience_rules_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
      event_invited_members: {
        Row: {
          attendance_type: string
          created_at: string | null
          event_id: string
          id: string
          member_id: string
          notes: string | null
        }
        Insert: {
          attendance_type?: string
          created_at?: string | null
          event_id: string
          id?: string
          member_id: string
          notes?: string | null
        }
        Update: {
          attendance_type?: string
          created_at?: string | null
          event_id?: string
          id?: string
          member_id?: string
          notes?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "event_invited_members_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_invited_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_invited_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "event_invited_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_invited_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_invited_members_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      event_showcases: {
        Row: {
          artifact_id: string | null
          board_item_id: string | null
          created_at: string
          duration_min: number | null
          event_id: string
          id: string
          member_id: string
          notes: string | null
          organization_id: string
          registered_by: string | null
          showcase_type: string
          title: string | null
          xp_awarded: number | null
        }
        Insert: {
          artifact_id?: string | null
          board_item_id?: string | null
          created_at?: string
          duration_min?: number | null
          event_id: string
          id?: string
          member_id: string
          notes?: string | null
          organization_id?: string
          registered_by?: string | null
          showcase_type: string
          title?: string | null
          xp_awarded?: number | null
        }
        Update: {
          artifact_id?: string | null
          board_item_id?: string | null
          created_at?: string
          duration_min?: number | null
          event_id?: string
          id?: string
          member_id?: string
          notes?: string | null
          organization_id?: string
          registered_by?: string | null
          showcase_type?: string
          title?: string | null
          xp_awarded?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "event_showcases_artifact_id_fkey"
            columns: ["artifact_id"]
            isOneToOne: false
            referencedRelation: "tribe_deliverables"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "event_showcases_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "event_showcases_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_showcases_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      event_tag_assignments: {
        Row: {
          created_at: string | null
          event_id: string
          id: string
          tag_id: string
        }
        Insert: {
          created_at?: string | null
          event_id: string
          id?: string
          tag_id: string
        }
        Update: {
          created_at?: string | null
          event_id?: string
          id?: string
          tag_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_tag_assignments_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_tag_assignments_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
        ]
      }
      events: {
        Row: {
          agenda_posted_at: string | null
          agenda_posted_by: string | null
          agenda_text: string | null
          agenda_url: string | null
          artia_activity_id: number | null
          artia_synced_at: string | null
          audience_level: string | null
          calendar_event_id: string | null
          cancellation_reason: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string | null
          created_by: string | null
          curation_status: string
          date: string
          duration_actual: number | null
          duration_minutes: number
          external_attendees: string[] | null
          external_calendar_provider: string | null
          id: string
          initiative_id: string | null
          invited_member_ids: string[] | null
          is_recorded: boolean | null
          last_synced_at: string | null
          meeting_link: string | null
          minutes_edit_history: Json | null
          minutes_edited_at: string | null
          minutes_posted_at: string | null
          minutes_posted_by: string | null
          minutes_text: string | null
          minutes_url: string | null
          nature: string | null
          notes: string | null
          organization_id: string
          recording_type: string | null
          recording_url: string | null
          recurrence_group: string | null
          rescheduled_from: string | null
          selection_application_id: string | null
          source: string | null
          status: string
          suggested_champion_ids: string[] | null
          sync_status: string | null
          time_start: string | null
          timezone: string | null
          title: string
          title_i18n: Json
          type: string
          updated_at: string | null
          visibility: string | null
          youtube_url: string | null
        }
        Insert: {
          agenda_posted_at?: string | null
          agenda_posted_by?: string | null
          agenda_text?: string | null
          agenda_url?: string | null
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          audience_level?: string | null
          calendar_event_id?: string | null
          cancellation_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string | null
          created_by?: string | null
          curation_status?: string
          date: string
          duration_actual?: number | null
          duration_minutes?: number
          external_attendees?: string[] | null
          external_calendar_provider?: string | null
          id?: string
          initiative_id?: string | null
          invited_member_ids?: string[] | null
          is_recorded?: boolean | null
          last_synced_at?: string | null
          meeting_link?: string | null
          minutes_edit_history?: Json | null
          minutes_edited_at?: string | null
          minutes_posted_at?: string | null
          minutes_posted_by?: string | null
          minutes_text?: string | null
          minutes_url?: string | null
          nature?: string | null
          notes?: string | null
          organization_id?: string
          recording_type?: string | null
          recording_url?: string | null
          recurrence_group?: string | null
          rescheduled_from?: string | null
          selection_application_id?: string | null
          source?: string | null
          status?: string
          suggested_champion_ids?: string[] | null
          sync_status?: string | null
          time_start?: string | null
          timezone?: string | null
          title: string
          title_i18n?: Json
          type: string
          updated_at?: string | null
          visibility?: string | null
          youtube_url?: string | null
        }
        Update: {
          agenda_posted_at?: string | null
          agenda_posted_by?: string | null
          agenda_text?: string | null
          agenda_url?: string | null
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          audience_level?: string | null
          calendar_event_id?: string | null
          cancellation_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string | null
          created_by?: string | null
          curation_status?: string
          date?: string
          duration_actual?: number | null
          duration_minutes?: number
          external_attendees?: string[] | null
          external_calendar_provider?: string | null
          id?: string
          initiative_id?: string | null
          invited_member_ids?: string[] | null
          is_recorded?: boolean | null
          last_synced_at?: string | null
          meeting_link?: string | null
          minutes_edit_history?: Json | null
          minutes_edited_at?: string | null
          minutes_posted_at?: string | null
          minutes_posted_by?: string | null
          minutes_text?: string | null
          minutes_url?: string | null
          nature?: string | null
          notes?: string | null
          organization_id?: string
          recording_type?: string | null
          recording_url?: string | null
          recurrence_group?: string | null
          rescheduled_from?: string | null
          selection_application_id?: string | null
          source?: string | null
          status?: string
          suggested_champion_ids?: string[] | null
          sync_status?: string | null
          time_start?: string | null
          timezone?: string | null
          title?: string
          title_i18n?: Json
          type?: string
          updated_at?: string | null
          visibility?: string | null
          youtube_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "events_agenda_posted_by_fkey"
            columns: ["agenda_posted_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_agenda_posted_by_fkey"
            columns: ["agenda_posted_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "events_agenda_posted_by_fkey"
            columns: ["agenda_posted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_agenda_posted_by_fkey"
            columns: ["agenda_posted_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_agenda_posted_by_fkey"
            columns: ["agenda_posted_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "events_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_minutes_posted_by_fkey"
            columns: ["minutes_posted_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_minutes_posted_by_fkey"
            columns: ["minutes_posted_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "events_minutes_posted_by_fkey"
            columns: ["minutes_posted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_minutes_posted_by_fkey"
            columns: ["minutes_posted_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_minutes_posted_by_fkey"
            columns: ["minutes_posted_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_rescheduled_from_fkey"
            columns: ["rescheduled_from"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
        ]
      }
      evm_analyses: {
        Row: {
          analysis_data: Json | null
          analysis_id: string | null
          created_at: string | null
          id: string
          project_name: string | null
          user_id: string | null
        }
        Insert: {
          analysis_data?: Json | null
          analysis_id?: string | null
          created_at?: string | null
          id?: string
          project_name?: string | null
          user_id?: string | null
        }
        Update: {
          analysis_data?: Json | null
          analysis_id?: string | null
          created_at?: string | null
          id?: string
          project_name?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      gamification_points: {
        Row: {
          category: string
          created_at: string | null
          id: string
          member_id: string
          organization_id: string
          points: number
          reason: string
          ref_id: string | null
        }
        Insert: {
          category: string
          created_at?: string | null
          id?: string
          member_id: string
          organization_id?: string
          points: number
          reason: string
          ref_id?: string | null
        }
        Update: {
          category?: string
          created_at?: string | null
          id?: string
          member_id?: string
          organization_id?: string
          points?: number
          reason?: string
          ref_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "gamification_points_category_fk"
            columns: ["organization_id", "category"]
            isOneToOne: false
            referencedRelation: "gamification_rules"
            referencedColumns: ["organization_id", "slug"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_points_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_points_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      gamification_rules: {
        Row: {
          active: boolean
          base_points: number
          bonus_per_criterion: number
          cap_points: number | null
          created_at: string
          created_by: string | null
          description_i18n: Json
          display_name_i18n: Json
          effective_from: string
          id: string
          organization_id: string
          pillar: string
          slug: string
          trigger_source: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          active?: boolean
          base_points: number
          bonus_per_criterion?: number
          cap_points?: number | null
          created_at?: string
          created_by?: string | null
          description_i18n?: Json
          display_name_i18n?: Json
          effective_from?: string
          id?: string
          organization_id: string
          pillar: string
          slug: string
          trigger_source: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          active?: boolean
          base_points?: number
          bonus_per_criterion?: number
          cap_points?: number | null
          created_at?: string
          created_by?: string | null
          description_i18n?: Json
          display_name_i18n?: Json
          effective_from?: string
          id?: string
          organization_id?: string
          pillar?: string
          slug?: string
          trigger_source?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "gamification_rules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "gamification_rules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "gamification_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_rules_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      gate_attempts: {
        Row: {
          application_id: string | null
          attempted_at: string | null
          bypass_granted: boolean | null
          bypass_requested: boolean | null
          caller_id: string | null
          gate_failed_code: string | null
          gate_failed_reason: string | null
          gate_passed: boolean
          id: string
          organization_id: string | null
          payload: Json | null
          rpc_name: string
        }
        Insert: {
          application_id?: string | null
          attempted_at?: string | null
          bypass_granted?: boolean | null
          bypass_requested?: boolean | null
          caller_id?: string | null
          gate_failed_code?: string | null
          gate_failed_reason?: string | null
          gate_passed: boolean
          id?: string
          organization_id?: string | null
          payload?: Json | null
          rpc_name: string
        }
        Update: {
          application_id?: string | null
          attempted_at?: string | null
          bypass_granted?: boolean | null
          bypass_requested?: boolean | null
          caller_id?: string | null
          gate_failed_code?: string | null
          gate_failed_reason?: string | null
          gate_passed?: boolean
          id?: string
          organization_id?: string | null
          payload?: Json | null
          rpc_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "gate_attempts_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gate_attempts_caller_id_fkey"
            columns: ["caller_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gate_attempts_caller_id_fkey"
            columns: ["caller_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "gate_attempts_caller_id_fkey"
            columns: ["caller_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gate_attempts_caller_id_fkey"
            columns: ["caller_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gate_attempts_caller_id_fkey"
            columns: ["caller_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      governance_documents: {
        Row: {
          artia_activity_id: number | null
          artia_synced_at: string | null
          content: Json | null
          created_at: string
          current_ratified_at: string | null
          current_ratified_chain_id: string | null
          current_ratified_version_id: string | null
          current_version_id: string | null
          description: string | null
          doc_type: string
          docusign_envelope_id: string | null
          exit_notice_days: number | null
          first_ratified_at: string | null
          first_ratified_chain_id: string | null
          first_ratified_version_id: string | null
          id: string
          initiative_id: string | null
          parties: string[] | null
          partner_entity_id: string | null
          pdf_url: string | null
          related_manual_sections: string[] | null
          signatories: Json | null
          signed_at: string | null
          status: string
          title: string
          updated_at: string
          valid_from: string | null
          valid_until: string | null
          version: string | null
        }
        Insert: {
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          content?: Json | null
          created_at?: string
          current_ratified_at?: string | null
          current_ratified_chain_id?: string | null
          current_ratified_version_id?: string | null
          current_version_id?: string | null
          description?: string | null
          doc_type: string
          docusign_envelope_id?: string | null
          exit_notice_days?: number | null
          first_ratified_at?: string | null
          first_ratified_chain_id?: string | null
          first_ratified_version_id?: string | null
          id?: string
          initiative_id?: string | null
          parties?: string[] | null
          partner_entity_id?: string | null
          pdf_url?: string | null
          related_manual_sections?: string[] | null
          signatories?: Json | null
          signed_at?: string | null
          status?: string
          title: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
          version?: string | null
        }
        Update: {
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          content?: Json | null
          created_at?: string
          current_ratified_at?: string | null
          current_ratified_chain_id?: string | null
          current_ratified_version_id?: string | null
          current_version_id?: string | null
          description?: string | null
          doc_type?: string
          docusign_envelope_id?: string | null
          exit_notice_days?: number | null
          first_ratified_at?: string | null
          first_ratified_chain_id?: string | null
          first_ratified_version_id?: string | null
          id?: string
          initiative_id?: string | null
          parties?: string[] | null
          partner_entity_id?: string | null
          pdf_url?: string | null
          related_manual_sections?: string[] | null
          signatories?: Json | null
          signed_at?: string | null
          status?: string
          title?: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
          version?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "governance_docs_current_ratified_chain_fk"
            columns: ["current_ratified_chain_id"]
            isOneToOne: false
            referencedRelation: "approval_chains"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "governance_docs_current_ratified_version_fk"
            columns: ["current_ratified_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "governance_docs_first_ratified_chain_fk"
            columns: ["first_ratified_chain_id"]
            isOneToOne: false
            referencedRelation: "approval_chains"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "governance_docs_first_ratified_version_fk"
            columns: ["first_ratified_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "governance_documents_current_version_id_fkey"
            columns: ["current_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "governance_documents_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "governance_documents_partner_entity_id_fkey"
            columns: ["partner_entity_id"]
            isOneToOne: false
            referencedRelation: "partner_entities"
            referencedColumns: ["id"]
          },
        ]
      }
      help_journeys: {
        Row: {
          created_at: string | null
          display_order: number | null
          icon: string | null
          id: string
          is_visible_to_visitors: boolean | null
          organization_id: string
          persona_key: string
          steps: Json
          subtitle: Json
          title: Json
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          display_order?: number | null
          icon?: string | null
          id?: string
          is_visible_to_visitors?: boolean | null
          organization_id?: string
          persona_key: string
          steps: Json
          subtitle: Json
          title: Json
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          display_order?: number | null
          icon?: string | null
          id?: string
          is_visible_to_visitors?: boolean | null
          organization_id?: string
          persona_key?: string
          steps?: Json
          subtitle?: Json
          title?: Json
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "help_journeys_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      home_schedule: {
        Row: {
          id: number
          kickoff_at: string
          platform_label: string
          recurring_end_brt: string
          recurring_start_brt: string
          recurring_weekday: number
          selection_deadline_at: string
          updated_at: string
        }
        Insert: {
          id?: number
          kickoff_at: string
          platform_label?: string
          recurring_end_brt: string
          recurring_start_brt: string
          recurring_weekday: number
          selection_deadline_at: string
          updated_at?: string
        }
        Update: {
          id?: number
          kickoff_at?: string
          platform_label?: string
          recurring_end_brt?: string
          recurring_start_brt?: string
          recurring_weekday?: number
          selection_deadline_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      hub_resources: {
        Row: {
          asset_type: string
          author_id: string | null
          course_id: number | null
          created_at: string
          curation_status: string
          cycle_code: string | null
          description: string | null
          id: string
          initiative_id: string | null
          is_active: boolean
          source: string | null
          tags: string[] | null
          title: string
          trello_card_id: string | null
          updated_at: string
          url: string | null
        }
        Insert: {
          asset_type: string
          author_id?: string | null
          course_id?: number | null
          created_at?: string
          curation_status?: string
          cycle_code?: string | null
          description?: string | null
          id?: string
          initiative_id?: string | null
          is_active?: boolean
          source?: string | null
          tags?: string[] | null
          title: string
          trello_card_id?: string | null
          updated_at?: string
          url?: string | null
        }
        Update: {
          asset_type?: string
          author_id?: string | null
          course_id?: number | null
          created_at?: string
          curation_status?: string
          cycle_code?: string | null
          description?: string | null
          id?: string
          initiative_id?: string | null
          is_active?: boolean
          source?: string | null
          tags?: string[] | null
          title?: string
          trello_card_id?: string | null
          updated_at?: string
          url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hub_resources_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
        ]
      }
      ia_pilots: {
        Row: {
          created_at: string | null
          cycle_code: string | null
          demo_url: string | null
          description: string | null
          end_date: string | null
          github_url: string | null
          id: string
          impact_metrics: Json | null
          initiative_id: string | null
          lead_member_id: string | null
          objectives: string[] | null
          organization_id: string
          results_summary: string | null
          start_date: string
          status: string | null
          technologies: string[] | null
          title: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          cycle_code?: string | null
          demo_url?: string | null
          description?: string | null
          end_date?: string | null
          github_url?: string | null
          id?: string
          impact_metrics?: Json | null
          initiative_id?: string | null
          lead_member_id?: string | null
          objectives?: string[] | null
          organization_id?: string
          results_summary?: string | null
          start_date: string
          status?: string | null
          technologies?: string[] | null
          title: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          cycle_code?: string | null
          demo_url?: string | null
          description?: string | null
          end_date?: string | null
          github_url?: string | null
          id?: string
          impact_metrics?: Json | null
          initiative_id?: string | null
          lead_member_id?: string | null
          objectives?: string[] | null
          organization_id?: string
          results_summary?: string | null
          start_date?: string
          status?: string | null
          technologies?: string[] | null
          title?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ia_pilots_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ia_pilots_lead_member_id_fkey"
            columns: ["lead_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ia_pilots_lead_member_id_fkey"
            columns: ["lead_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ia_pilots_lead_member_id_fkey"
            columns: ["lead_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ia_pilots_lead_member_id_fkey"
            columns: ["lead_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ia_pilots_lead_member_id_fkey"
            columns: ["lead_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ia_pilots_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_remediation_escalation_matrix: {
        Row: {
          action_type: string
          enabled: boolean
          priority: number
          recurrence_threshold: number
          severity: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          action_type: string
          enabled?: boolean
          priority?: number
          recurrence_threshold: number
          severity: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          action_type?: string
          enabled?: boolean
          priority?: number
          recurrence_threshold?: number
          severity?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_remediation_escalation_matrix_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_source_controls: {
        Row: {
          allow_apply: boolean
          notes: string | null
          require_manual_review: boolean
          source: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          allow_apply?: boolean
          notes?: string | null
          require_manual_review?: boolean
          source: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          allow_apply?: boolean
          notes?: string | null
          require_manual_review?: boolean
          source?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_controls_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      ingestion_source_sla: {
        Row: {
          enabled: boolean
          escalation_severity: string
          expected_max_minutes: number
          source: string
          timeout_minutes: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          enabled?: boolean
          escalation_severity?: string
          expected_max_minutes?: number
          source: string
          timeout_minutes?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          enabled?: boolean
          escalation_severity?: string
          expected_max_minutes?: number
          source?: string
          timeout_minutes?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ingestion_source_sla_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      initiative_drive_links: {
        Row: {
          drive_folder_id: string
          drive_folder_name: string | null
          drive_folder_url: string
          id: string
          initiative_id: string
          link_purpose: string | null
          linked_at: string
          linked_by: string
          unlinked_at: string | null
          unlinked_by: string | null
        }
        Insert: {
          drive_folder_id: string
          drive_folder_name?: string | null
          drive_folder_url: string
          id?: string
          initiative_id: string
          link_purpose?: string | null
          linked_at?: string
          linked_by: string
          unlinked_at?: string | null
          unlinked_by?: string | null
        }
        Update: {
          drive_folder_id?: string
          drive_folder_name?: string | null
          drive_folder_url?: string
          id?: string
          initiative_id?: string
          link_purpose?: string | null
          linked_at?: string
          linked_by?: string
          unlinked_at?: string | null
          unlinked_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "initiative_drive_links_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "initiative_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_linked_by_fkey"
            columns: ["linked_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "initiative_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_drive_links_unlinked_by_fkey"
            columns: ["unlinked_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      initiative_invitations: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          initiative_id: string
          invitee_member_id: string
          inviter_member_id: string
          kind_scope: string
          message: string
          responded_at: string | null
          responded_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          reviewed_note: string | null
          revoked_at: string | null
          revoked_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          expires_at?: string
          id?: string
          initiative_id: string
          invitee_member_id: string
          inviter_member_id: string
          kind_scope: string
          message: string
          responded_at?: string | null
          responded_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewed_note?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          initiative_id?: string
          invitee_member_id?: string
          inviter_member_id?: string
          kind_scope?: string
          message?: string
          responded_at?: string | null
          responded_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewed_note?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "initiative_invitations_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_invitee_member_id_fkey"
            columns: ["invitee_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_invitee_member_id_fkey"
            columns: ["invitee_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "initiative_invitations_invitee_member_id_fkey"
            columns: ["invitee_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_invitee_member_id_fkey"
            columns: ["invitee_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_invitee_member_id_fkey"
            columns: ["invitee_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_inviter_member_id_fkey"
            columns: ["inviter_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_inviter_member_id_fkey"
            columns: ["inviter_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "initiative_invitations_inviter_member_id_fkey"
            columns: ["inviter_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_inviter_member_id_fkey"
            columns: ["inviter_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_inviter_member_id_fkey"
            columns: ["inviter_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "initiative_invitations_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "initiative_invitations_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_invitations_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      initiative_kinds: {
        Row: {
          allowed_engagement_kinds: string[]
          certificate_template_id: string | null
          created_at: string
          created_by: string | null
          custom_fields_schema: Json
          default_duration_days: number | null
          description: string | null
          display_name: string
          has_attendance: boolean
          has_board: boolean
          has_certificate: boolean
          has_deliverables: boolean
          has_meeting_notes: boolean
          icon: string | null
          icon_emoji: string | null
          lifecycle_states: string[]
          max_concurrent_per_org: number | null
          organization_id: string
          required_engagement_kinds: string[]
          slug: string
          updated_at: string
        }
        Insert: {
          allowed_engagement_kinds?: string[]
          certificate_template_id?: string | null
          created_at?: string
          created_by?: string | null
          custom_fields_schema?: Json
          default_duration_days?: number | null
          description?: string | null
          display_name: string
          has_attendance?: boolean
          has_board?: boolean
          has_certificate?: boolean
          has_deliverables?: boolean
          has_meeting_notes?: boolean
          icon?: string | null
          icon_emoji?: string | null
          lifecycle_states?: string[]
          max_concurrent_per_org?: number | null
          organization_id?: string
          required_engagement_kinds?: string[]
          slug: string
          updated_at?: string
        }
        Update: {
          allowed_engagement_kinds?: string[]
          certificate_template_id?: string | null
          created_at?: string
          created_by?: string | null
          custom_fields_schema?: Json
          default_duration_days?: number | null
          description?: string | null
          display_name?: string
          has_attendance?: boolean
          has_board?: boolean
          has_certificate?: boolean
          has_deliverables?: boolean
          has_meeting_notes?: boolean
          icon?: string | null
          icon_emoji?: string | null
          lifecycle_states?: string[]
          max_concurrent_per_org?: number | null
          organization_id?: string
          required_engagement_kinds?: string[]
          slug?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "initiative_kinds_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      initiative_member_progress: {
        Row: {
          id: string
          initiative_id: string
          organization_id: string
          payload: Json
          person_id: string
          progress_type: string
          recorded_at: string
        }
        Insert: {
          id?: string
          initiative_id: string
          organization_id?: string
          payload?: Json
          person_id: string
          progress_type: string
          recorded_at?: string
        }
        Update: {
          id?: string
          initiative_id?: string
          organization_id?: string
          payload?: Json
          person_id?: string
          progress_type?: string
          recorded_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "initiative_member_progress_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_member_progress_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiative_member_progress_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      initiatives: {
        Row: {
          artia_activity_id: number | null
          artia_folder_id: number | null
          artia_synced_at: string | null
          created_at: string
          description: string | null
          id: string
          join_policy: string
          kind: string
          legacy_tribe_id: number | null
          metadata: Json
          organization_id: string
          origin_partner_entity_id: string | null
          parent_initiative_id: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          artia_activity_id?: number | null
          artia_folder_id?: number | null
          artia_synced_at?: string | null
          created_at?: string
          description?: string | null
          id?: string
          join_policy?: string
          kind: string
          legacy_tribe_id?: number | null
          metadata?: Json
          organization_id?: string
          origin_partner_entity_id?: string | null
          parent_initiative_id?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          artia_activity_id?: number | null
          artia_folder_id?: number | null
          artia_synced_at?: string | null
          created_at?: string
          description?: string | null
          id?: string
          join_policy?: string
          kind?: string
          legacy_tribe_id?: number | null
          metadata?: Json
          organization_id?: string
          origin_partner_entity_id?: string | null
          parent_initiative_id?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "initiatives_kind_fkey"
            columns: ["kind"]
            isOneToOne: false
            referencedRelation: "initiative_kinds"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "initiatives_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiatives_origin_partner_entity_id_fkey"
            columns: ["origin_partner_entity_id"]
            isOneToOne: false
            referencedRelation: "partner_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "initiatives_parent_initiative_id_fkey"
            columns: ["parent_initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_assets: {
        Row: {
          created_at: string
          created_by: string | null
          external_id: string
          id: string
          is_active: boolean
          language: string
          metadata: Json
          published_at: string | null
          source: string
          source_url: string | null
          summary: string | null
          tags: string[]
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          external_id: string
          id?: string
          is_active?: boolean
          language?: string
          metadata?: Json
          published_at?: string | null
          source: string
          source_url?: string | null
          summary?: string | null
          tags?: string[]
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          external_id?: string
          id?: string
          is_active?: boolean
          language?: string
          metadata?: Json
          published_at?: string | null
          source?: string
          source_url?: string | null
          summary?: string | null
          tags?: string[]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_chunks: {
        Row: {
          asset_id: string
          chunk_index: number
          content: string
          created_at: string
          embedding: string | null
          id: string
          metadata: Json
          token_estimate: number | null
        }
        Insert: {
          asset_id: string
          chunk_index: number
          content: string
          created_at?: string
          embedding?: string | null
          id?: string
          metadata?: Json
          token_estimate?: number | null
        }
        Update: {
          asset_id?: string
          chunk_index?: number
          content?: string
          created_at?: string
          embedding?: string | null
          id?: string
          metadata?: Json
          token_estimate?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_chunks_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "knowledge_assets"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_ingestion_runs: {
        Row: {
          created_at: string
          error_message: string | null
          id: string
          metadata: Json
          rows_chunked: number
          rows_received: number
          rows_upserted: number
          run_key: string
          source: string
          status: string
          triggered_by: string | null
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          id?: string
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key: string
          source: string
          status: string
          triggered_by?: string | null
        }
        Update: {
          created_at?: string
          error_message?: string | null
          id?: string
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key?: string
          source?: string
          status?: string
          triggered_by?: string | null
        }
        Relationships: []
      }
      knowledge_insights: {
        Row: {
          asset_id: string | null
          chunk_id: string | null
          confidence_score: number | null
          created_at: string
          detected_at: string
          evidence_quote: string | null
          evidence_url: string | null
          id: string
          impact_score: number
          insight_type: string
          metadata: Json
          reviewed_at: string | null
          reviewed_by: string | null
          sentiment_score: number | null
          source: string
          status: string
          summary: string
          taxonomy_area: string
          title: string
          updated_at: string
          urgency_score: number
        }
        Insert: {
          asset_id?: string | null
          chunk_id?: string | null
          confidence_score?: number | null
          created_at?: string
          detected_at?: string
          evidence_quote?: string | null
          evidence_url?: string | null
          id?: string
          impact_score?: number
          insight_type: string
          metadata?: Json
          reviewed_at?: string | null
          reviewed_by?: string | null
          sentiment_score?: number | null
          source: string
          status?: string
          summary: string
          taxonomy_area: string
          title: string
          updated_at?: string
          urgency_score?: number
        }
        Update: {
          asset_id?: string | null
          chunk_id?: string | null
          confidence_score?: number | null
          created_at?: string
          detected_at?: string
          evidence_quote?: string | null
          evidence_url?: string | null
          id?: string
          impact_score?: number
          insight_type?: string
          metadata?: Json
          reviewed_at?: string | null
          reviewed_by?: string | null
          sentiment_score?: number | null
          source?: string
          status?: string
          summary?: string
          taxonomy_area?: string
          title?: string
          updated_at?: string
          urgency_score?: number
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_insights_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "knowledge_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_chunk_id_fkey"
            columns: ["chunk_id"]
            isOneToOne: false
            referencedRelation: "knowledge_chunks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "knowledge_insights_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_insights_ingestion_log: {
        Row: {
          created_at: string
          error_message: string | null
          finished_at: string | null
          id: number
          metadata: Json
          rows_chunked: number
          rows_received: number
          rows_upserted: number
          run_key: string
          status: string
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          finished_at?: string | null
          id?: number
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key: string
          status: string
        }
        Update: {
          created_at?: string
          error_message?: string | null
          finished_at?: string | null
          id?: number
          metadata?: Json
          rows_chunked?: number
          rows_received?: number
          rows_upserted?: number
          run_key?: string
          status?: string
        }
        Relationships: []
      }
      manual_sections: {
        Row: {
          approved_at: string | null
          approved_by: string[] | null
          content_en: string | null
          content_es: string | null
          content_pt: string | null
          created_at: string
          id: string
          is_current: boolean
          manual_version: string
          page_end: number | null
          page_start: number | null
          parent_section_id: string | null
          section_number: string
          sort_order: number
          title_en: string | null
          title_es: string | null
          title_pt: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string[] | null
          content_en?: string | null
          content_es?: string | null
          content_pt?: string | null
          created_at?: string
          id?: string
          is_current?: boolean
          manual_version?: string
          page_end?: number | null
          page_start?: number | null
          parent_section_id?: string | null
          section_number: string
          sort_order?: number
          title_en?: string | null
          title_es?: string | null
          title_pt: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string[] | null
          content_en?: string | null
          content_es?: string | null
          content_pt?: string | null
          created_at?: string
          id?: string
          is_current?: boolean
          manual_version?: string
          page_end?: number | null
          page_start?: number | null
          parent_section_id?: string | null
          section_number?: string
          sort_order?: number
          title_en?: string | null
          title_es?: string | null
          title_pt?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "manual_sections_parent_section_id_fkey"
            columns: ["parent_section_id"]
            isOneToOne: false
            referencedRelation: "manual_sections"
            referencedColumns: ["id"]
          },
        ]
      }
      mcp_usage_log: {
        Row: {
          auth_user_id: string | null
          created_at: string | null
          error_message: string | null
          execution_ms: number | null
          id: string
          member_id: string | null
          organization_id: string | null
          response_summary: Json | null
          result_kind: string
          success: boolean | null
          tool_name: string
        }
        Insert: {
          auth_user_id?: string | null
          created_at?: string | null
          error_message?: string | null
          execution_ms?: number | null
          id?: string
          member_id?: string | null
          organization_id?: string | null
          response_summary?: Json | null
          result_kind?: string
          success?: boolean | null
          tool_name: string
        }
        Update: {
          auth_user_id?: string | null
          created_at?: string | null
          error_message?: string | null
          execution_ms?: number | null
          id?: string
          member_id?: string | null
          organization_id?: string | null
          response_summary?: Json | null
          result_kind?: string
          success?: boolean | null
          tool_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "mcp_usage_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mcp_usage_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "mcp_usage_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mcp_usage_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mcp_usage_log_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mcp_usage_log_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      meeting_action_items: {
        Row: {
          assignee_id: string | null
          assignee_name: string | null
          board_item_id: string | null
          carried_to_event_id: string | null
          checklist_item_id: string | null
          created_at: string | null
          created_by: string | null
          description: string
          due_date: string | null
          event_id: string
          id: string
          kind: string | null
          resolution_note: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: string | null
          updated_at: string | null
        }
        Insert: {
          assignee_id?: string | null
          assignee_name?: string | null
          board_item_id?: string | null
          carried_to_event_id?: string | null
          checklist_item_id?: string | null
          created_at?: string | null
          created_by?: string | null
          description: string
          due_date?: string | null
          event_id: string
          id?: string
          kind?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          assignee_id?: string | null
          assignee_name?: string | null
          board_item_id?: string | null
          carried_to_event_id?: string | null
          checklist_item_id?: string | null
          created_at?: string | null
          created_by?: string | null
          description?: string
          due_date?: string | null
          event_id?: string
          id?: string
          kind?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "meeting_action_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "meeting_action_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_carried_to_event_id_fkey"
            columns: ["carried_to_event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_checklist_item_id_fkey"
            columns: ["checklist_item_id"]
            isOneToOne: false
            referencedRelation: "board_item_checklists"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "meeting_action_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "meeting_action_items_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_action_items_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      meeting_artifacts: {
        Row: {
          agenda_items: string[] | null
          created_at: string
          created_by: string | null
          cycle_code: string | null
          deliberations: string[] | null
          event_id: string | null
          id: string
          initiative_id: string | null
          is_published: boolean
          meeting_date: string
          organization_id: string
          page_data_snapshot: Json | null
          recording_url: string | null
          title: string
          updated_at: string
        }
        Insert: {
          agenda_items?: string[] | null
          created_at?: string
          created_by?: string | null
          cycle_code?: string | null
          deliberations?: string[] | null
          event_id?: string | null
          id?: string
          initiative_id?: string | null
          is_published?: boolean
          meeting_date: string
          organization_id?: string
          page_data_snapshot?: Json | null
          recording_url?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          agenda_items?: string[] | null
          created_at?: string
          created_by?: string | null
          cycle_code?: string | null
          deliberations?: string[] | null
          event_id?: string | null
          id?: string
          initiative_id?: string | null
          is_published?: boolean
          meeting_date?: string
          organization_id?: string
          page_data_snapshot?: Json | null
          recording_url?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_artifacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      member_activity_sessions: {
        Row: {
          created_at: string | null
          first_page: string | null
          id: string
          last_page: string | null
          member_id: string
          organization_id: string
          pages_visited: number | null
          session_date: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          first_page?: string | null
          id?: string
          last_page?: string | null
          member_id: string
          organization_id?: string
          pages_visited?: number | null
          session_date?: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          first_page?: string | null
          id?: string
          last_page?: string | null
          member_id?: string
          organization_id?: string
          pages_visited?: number | null
          session_date?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_activity_sessions_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_activity_sessions_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_activity_sessions_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_activity_sessions_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_activity_sessions_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_activity_sessions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      member_cycle_history: {
        Row: {
          chapter: string | null
          created_at: string | null
          cycle_code: string
          cycle_end: string | null
          cycle_label: string
          cycle_start: string | null
          designations: string[] | null
          id: string
          is_active: boolean | null
          member_id: string | null
          member_name_snapshot: string
          notes: string | null
          operational_role: string
          tribe_id: number | null
          tribe_name: string | null
        }
        Insert: {
          chapter?: string | null
          created_at?: string | null
          cycle_code: string
          cycle_end?: string | null
          cycle_label: string
          cycle_start?: string | null
          designations?: string[] | null
          id?: string
          is_active?: boolean | null
          member_id?: string | null
          member_name_snapshot: string
          notes?: string | null
          operational_role?: string
          tribe_id?: number | null
          tribe_name?: string | null
        }
        Update: {
          chapter?: string | null
          created_at?: string | null
          cycle_code?: string
          cycle_end?: string | null
          cycle_label?: string
          cycle_start?: string | null
          designations?: string[] | null
          id?: string
          is_active?: boolean | null
          member_id?: string | null
          member_name_snapshot?: string
          notes?: string | null
          operational_role?: string
          tribe_id?: number | null
          tribe_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_cycle_history_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      member_document_signatures: {
        Row: {
          approval_chain_id: string | null
          certificate_id: string | null
          created_at: string
          document_id: string
          id: string
          is_current: boolean
          member_id: string
          signed_at: string
          signed_version_id: string
          signoff_id: string | null
          superseded_at: string | null
          superseded_by_version_id: string | null
          updated_at: string
        }
        Insert: {
          approval_chain_id?: string | null
          certificate_id?: string | null
          created_at?: string
          document_id: string
          id?: string
          is_current?: boolean
          member_id: string
          signed_at?: string
          signed_version_id: string
          signoff_id?: string | null
          superseded_at?: string | null
          superseded_by_version_id?: string | null
          updated_at?: string
        }
        Update: {
          approval_chain_id?: string | null
          certificate_id?: string | null
          created_at?: string
          document_id?: string
          id?: string
          is_current?: boolean
          member_id?: string
          signed_at?: string
          signed_version_id?: string
          signoff_id?: string | null
          superseded_at?: string | null
          superseded_by_version_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_document_signatures_approval_chain_id_fkey"
            columns: ["approval_chain_id"]
            isOneToOne: false
            referencedRelation: "approval_chains"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_certificate_id_fkey"
            columns: ["certificate_id"]
            isOneToOne: false
            referencedRelation: "certificates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "governance_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_document_signatures_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_signed_version_id_fkey"
            columns: ["signed_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_signoff_id_fkey"
            columns: ["signoff_id"]
            isOneToOne: false
            referencedRelation: "approval_signoffs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_document_signatures_superseded_by_version_id_fkey"
            columns: ["superseded_by_version_id"]
            isOneToOne: false
            referencedRelation: "document_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      member_emails: {
        Row: {
          added_at: string
          email: string
          id: string
          is_primary: boolean
          kind: string
          member_id: string
          organization_id: string | null
        }
        Insert: {
          added_at?: string
          email: string
          id?: string
          is_primary?: boolean
          kind: string
          member_id: string
          organization_id?: string | null
        }
        Update: {
          added_at?: string
          email?: string
          id?: string
          is_primary?: boolean
          kind?: string
          member_id?: string
          organization_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "member_emails_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_emails_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_emails_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_emails_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_emails_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_emails_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      member_offboarding_records: {
        Row: {
          attachment_urls: string[] | null
          chapter_at_offboard: string | null
          created_at: string
          cycle_code_at_offboard: string | null
          exit_interview_full_text: string | null
          exit_interview_source: string | null
          id: string
          lessons_learned: string | null
          member_id: string
          offboarded_at: string
          offboarded_by: string | null
          reason_category_code: string
          reason_detail: string | null
          recommendation_for_future: string | null
          referred_by_tribe_leader: boolean | null
          return_interest: boolean | null
          return_window_suggestion: string | null
          tribe_id_at_offboard: number | null
          updated_at: string
        }
        Insert: {
          attachment_urls?: string[] | null
          chapter_at_offboard?: string | null
          created_at?: string
          cycle_code_at_offboard?: string | null
          exit_interview_full_text?: string | null
          exit_interview_source?: string | null
          id?: string
          lessons_learned?: string | null
          member_id: string
          offboarded_at: string
          offboarded_by?: string | null
          reason_category_code: string
          reason_detail?: string | null
          recommendation_for_future?: string | null
          referred_by_tribe_leader?: boolean | null
          return_interest?: boolean | null
          return_window_suggestion?: string | null
          tribe_id_at_offboard?: number | null
          updated_at?: string
        }
        Update: {
          attachment_urls?: string[] | null
          chapter_at_offboard?: string | null
          created_at?: string
          cycle_code_at_offboard?: string | null
          exit_interview_full_text?: string | null
          exit_interview_source?: string | null
          id?: string
          lessons_learned?: string | null
          member_id?: string
          offboarded_at?: string
          offboarded_by?: string | null
          reason_category_code?: string
          reason_detail?: string | null
          recommendation_for_future?: string | null
          referred_by_tribe_leader?: boolean | null
          return_interest?: boolean | null
          return_window_suggestion?: string | null
          tribe_id_at_offboard?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_offboarding_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_offboarding_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_offboarding_records_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_offboarding_records_reason_category_code_fkey"
            columns: ["reason_category_code"]
            isOneToOne: false
            referencedRelation: "offboard_reason_categories"
            referencedColumns: ["code"]
          },
        ]
      }
      member_quick_start_progress: {
        Row: {
          completed_steps: number[]
          created_at: string
          last_updated: string
          member_id: string
          organization_id: string
          total_steps: number
        }
        Insert: {
          completed_steps?: number[]
          created_at?: string
          last_updated?: string
          member_id: string
          organization_id?: string
          total_steps?: number
        }
        Update: {
          completed_steps?: number[]
          created_at?: string
          last_updated?: string
          member_id?: string
          organization_id?: string
          total_steps?: number
        }
        Relationships: [
          {
            foreignKeyName: "member_quick_start_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_quick_start_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "member_quick_start_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_quick_start_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_quick_start_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      members: {
        Row: {
          address: string | null
          anonymized_at: string | null
          anonymized_by: string | null
          auth_id: string | null
          birth_date: string | null
          chapter: string
          city: string | null
          country: string | null
          cpmai_certified: boolean | null
          cpmai_certified_at: string | null
          created_at: string | null
          credly_badges: Json | null
          credly_url: string | null
          credly_verified_at: string | null
          current_cycle_active: boolean | null
          cycles: string[] | null
          data_last_reviewed_at: string | null
          designations: string[] | null
          email: string
          gamification_opt_out: boolean
          id: string
          inactivated_at: string | null
          inactivation_reason: string | null
          initiative_id: string | null
          is_active: boolean | null
          is_superadmin: boolean | null
          last_active_pages: string[] | null
          last_seen_at: string | null
          linkedin_url: string | null
          member_status: string | null
          name: string
          notify_delivery_mode_pref: string
          notify_weekly_digest: boolean
          offboarded_at: string | null
          offboarded_by: string | null
          onboarding_dismissed_at: string | null
          operational_role: string | null
          organization_id: string
          person_id: string | null
          phone: string | null
          phone_encrypted: string | null
          photo_url: string | null
          pmi_id: string | null
          pmi_id_encrypted: string | null
          pmi_id_verified: boolean | null
          privacy_consent_accepted_at: string | null
          privacy_consent_version: string | null
          profile_completed_at: string | null
          secondary_auth_ids: string[] | null
          secondary_emails: string[] | null
          share_address: boolean | null
          share_birth_date: boolean | null
          share_whatsapp: boolean
          signature_url: string | null
          state: string | null
          status_change_reason: string | null
          status_changed_at: string | null
          total_sessions: number | null
          tribe_id: number | null
          updated_at: string | null
        }
        Insert: {
          address?: string | null
          anonymized_at?: string | null
          anonymized_by?: string | null
          auth_id?: string | null
          birth_date?: string | null
          chapter?: string
          city?: string | null
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          data_last_reviewed_at?: string | null
          designations?: string[] | null
          email: string
          gamification_opt_out?: boolean
          id?: string
          inactivated_at?: string | null
          inactivation_reason?: string | null
          initiative_id?: string | null
          is_active?: boolean | null
          is_superadmin?: boolean | null
          last_active_pages?: string[] | null
          last_seen_at?: string | null
          linkedin_url?: string | null
          member_status?: string | null
          name: string
          notify_delivery_mode_pref?: string
          notify_weekly_digest?: boolean
          offboarded_at?: string | null
          offboarded_by?: string | null
          onboarding_dismissed_at?: string | null
          operational_role?: string | null
          organization_id?: string
          person_id?: string | null
          phone?: string | null
          phone_encrypted?: string | null
          photo_url?: string | null
          pmi_id?: string | null
          pmi_id_encrypted?: string | null
          pmi_id_verified?: boolean | null
          privacy_consent_accepted_at?: string | null
          privacy_consent_version?: string | null
          profile_completed_at?: string | null
          secondary_auth_ids?: string[] | null
          secondary_emails?: string[] | null
          share_address?: boolean | null
          share_birth_date?: boolean | null
          share_whatsapp?: boolean
          signature_url?: string | null
          state?: string | null
          status_change_reason?: string | null
          status_changed_at?: string | null
          total_sessions?: number | null
          tribe_id?: number | null
          updated_at?: string | null
        }
        Update: {
          address?: string | null
          anonymized_at?: string | null
          anonymized_by?: string | null
          auth_id?: string | null
          birth_date?: string | null
          chapter?: string
          city?: string | null
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          data_last_reviewed_at?: string | null
          designations?: string[] | null
          email?: string
          gamification_opt_out?: boolean
          id?: string
          inactivated_at?: string | null
          inactivation_reason?: string | null
          initiative_id?: string | null
          is_active?: boolean | null
          is_superadmin?: boolean | null
          last_active_pages?: string[] | null
          last_seen_at?: string | null
          linkedin_url?: string | null
          member_status?: string | null
          name?: string
          notify_delivery_mode_pref?: string
          notify_weekly_digest?: boolean
          offboarded_at?: string | null
          offboarded_by?: string | null
          onboarding_dismissed_at?: string | null
          operational_role?: string | null
          organization_id?: string
          person_id?: string | null
          phone?: string | null
          phone_encrypted?: string | null
          photo_url?: string | null
          pmi_id?: string | null
          pmi_id_encrypted?: string | null
          pmi_id_verified?: boolean | null
          privacy_consent_accepted_at?: string | null
          privacy_consent_version?: string | null
          profile_completed_at?: string | null
          secondary_auth_ids?: string[] | null
          secondary_emails?: string[] | null
          share_address?: boolean | null
          share_birth_date?: boolean | null
          share_whatsapp?: boolean
          signature_url?: string | null
          state?: string | null
          status_change_reason?: string | null
          status_changed_at?: string | null
          total_sessions?: number | null
          tribe_id?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "members_anonymized_by_fkey"
            columns: ["anonymized_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_anonymized_by_fkey"
            columns: ["anonymized_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "members_anonymized_by_fkey"
            columns: ["anonymized_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_anonymized_by_fkey"
            columns: ["anonymized_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_anonymized_by_fkey"
            columns: ["anonymized_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "members_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_offboarded_by_fkey"
            columns: ["offboarded_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          digest_frequency: string | null
          email_digest: boolean | null
          enabled: boolean | null
          in_app: boolean | null
          member_id: string
          muted_types: string[] | null
          updated_at: string | null
        }
        Insert: {
          digest_frequency?: string | null
          email_digest?: boolean | null
          enabled?: boolean | null
          in_app?: boolean | null
          member_id: string
          muted_types?: string[] | null
          updated_at?: string | null
        }
        Update: {
          digest_frequency?: string | null
          email_digest?: boolean | null
          enabled?: boolean | null
          in_app?: boolean | null
          member_id?: string
          muted_types?: string[] | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_preferences_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "notification_preferences_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_preferences_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_preferences_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          actor_id: string | null
          body: string | null
          created_at: string | null
          delivery_mode: string
          digest_batch_id: string | null
          digest_delivered_at: string | null
          email_sent_at: string | null
          id: string
          is_read: boolean | null
          link: string | null
          read_at: string | null
          recipient_id: string
          source_id: string | null
          source_type: string | null
          title: string
          type: string
        }
        Insert: {
          actor_id?: string | null
          body?: string | null
          created_at?: string | null
          delivery_mode?: string
          digest_batch_id?: string | null
          digest_delivered_at?: string | null
          email_sent_at?: string | null
          id?: string
          is_read?: boolean | null
          link?: string | null
          read_at?: string | null
          recipient_id: string
          source_id?: string | null
          source_type?: string | null
          title: string
          type: string
        }
        Update: {
          actor_id?: string | null
          body?: string | null
          created_at?: string | null
          delivery_mode?: string
          digest_batch_id?: string | null
          digest_delivered_at?: string | null
          email_sent_at?: string | null
          id?: string
          is_read?: boolean | null
          link?: string | null
          read_at?: string | null
          recipient_id?: string
          source_id?: string | null
          source_type?: string | null
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "notifications_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      offboard_reason_categories: {
        Row: {
          code: string
          created_at: string
          description_pt: string | null
          is_active: boolean | null
          is_volunteer_fault: boolean | null
          label_en: string | null
          label_es: string | null
          label_pt: string
          preserves_return_eligibility: boolean | null
          sort_order: number | null
        }
        Insert: {
          code: string
          created_at?: string
          description_pt?: string | null
          is_active?: boolean | null
          is_volunteer_fault?: boolean | null
          label_en?: string | null
          label_es?: string | null
          label_pt: string
          preserves_return_eligibility?: boolean | null
          sort_order?: number | null
        }
        Update: {
          code?: string
          created_at?: string
          description_pt?: string | null
          is_active?: boolean | null
          is_volunteer_fault?: boolean | null
          label_en?: string | null
          label_es?: string | null
          label_pt?: string
          preserves_return_eligibility?: boolean | null
          sort_order?: number | null
        }
        Relationships: []
      }
      onboarding_progress: {
        Row: {
          application_id: string | null
          completed_at: string | null
          created_at: string | null
          evidence_url: string | null
          id: string
          member_id: string | null
          metadata: Json | null
          notes: string | null
          sla_deadline: string | null
          status: string
          step_key: string
          updated_at: string | null
        }
        Insert: {
          application_id?: string | null
          completed_at?: string | null
          created_at?: string | null
          evidence_url?: string | null
          id?: string
          member_id?: string | null
          metadata?: Json | null
          notes?: string | null
          sla_deadline?: string | null
          status?: string
          step_key: string
          updated_at?: string | null
        }
        Update: {
          application_id?: string | null
          completed_at?: string | null
          created_at?: string | null
          evidence_url?: string | null
          id?: string
          member_id?: string | null
          metadata?: Json | null
          notes?: string | null
          sla_deadline?: string | null
          status?: string
          step_key?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "onboarding_progress_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "onboarding_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "onboarding_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "onboarding_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "onboarding_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "onboarding_progress_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      onboarding_steps: {
        Row: {
          created_at: string | null
          description_en: string | null
          description_es: string | null
          description_pt: string | null
          icon: string | null
          id: string
          is_required: boolean | null
          label_en: string
          label_es: string
          label_pt: string
          step_order: number
        }
        Insert: {
          created_at?: string | null
          description_en?: string | null
          description_es?: string | null
          description_pt?: string | null
          icon?: string | null
          id: string
          is_required?: boolean | null
          label_en: string
          label_es: string
          label_pt: string
          step_order: number
        }
        Update: {
          created_at?: string | null
          description_en?: string | null
          description_es?: string | null
          description_pt?: string | null
          icon?: string | null
          id?: string
          is_required?: boolean | null
          label_en?: string
          label_es?: string
          label_pt?: string
          step_order?: number
        }
        Relationships: []
      }
      onboarding_tokens: {
        Row: {
          access_count: number
          consumed_at: string | null
          expires_at: string
          issued_at: string
          issued_by: string | null
          issued_by_worker: string | null
          last_accessed_at: string | null
          organization_id: string
          scopes: string[]
          source_id: string
          source_type: string
          token: string
        }
        Insert: {
          access_count?: number
          consumed_at?: string | null
          expires_at: string
          issued_at?: string
          issued_by?: string | null
          issued_by_worker?: string | null
          last_accessed_at?: string | null
          organization_id?: string
          scopes?: string[]
          source_id: string
          source_type: string
          token: string
        }
        Update: {
          access_count?: number
          consumed_at?: string | null
          expires_at?: string
          issued_at?: string
          issued_by?: string | null
          issued_by_worker?: string | null
          last_accessed_at?: string | null
          organization_id?: string
          scopes?: string[]
          source_id?: string
          source_type?: string
          token?: string
        }
        Relationships: []
      }
      organizations: {
        Row: {
          country: string
          created_at: string
          description: string | null
          federated_chapters: string[]
          host_chapter: string | null
          id: string
          logo_url: string | null
          name: string
          primary_language: string
          slug: string
          status: string
          updated_at: string
          website_url: string | null
        }
        Insert: {
          country?: string
          created_at?: string
          description?: string | null
          federated_chapters?: string[]
          host_chapter?: string | null
          id?: string
          logo_url?: string | null
          name: string
          primary_language?: string
          slug: string
          status?: string
          updated_at?: string
          website_url?: string | null
        }
        Update: {
          country?: string
          created_at?: string
          description?: string | null
          federated_chapters?: string[]
          host_chapter?: string | null
          id?: string
          logo_url?: string | null
          name?: string
          primary_language?: string
          slug?: string
          status?: string
          updated_at?: string
          website_url?: string | null
        }
        Relationships: []
      }
      partner_attachments: {
        Row: {
          created_at: string | null
          description: string | null
          file_name: string
          file_size: number | null
          file_type: string | null
          file_url: string
          id: string
          partner_entity_id: string | null
          partner_interaction_id: string | null
          uploaded_by: string
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          file_name: string
          file_size?: number | null
          file_type?: string | null
          file_url: string
          id?: string
          partner_entity_id?: string | null
          partner_interaction_id?: string | null
          uploaded_by: string
        }
        Update: {
          created_at?: string | null
          description?: string | null
          file_name?: string
          file_size?: number | null
          file_type?: string | null
          file_url?: string
          id?: string
          partner_entity_id?: string | null
          partner_interaction_id?: string | null
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "partner_attachments_partner_entity_id_fkey"
            columns: ["partner_entity_id"]
            isOneToOne: false
            referencedRelation: "partner_entities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_attachments_partner_interaction_id_fkey"
            columns: ["partner_interaction_id"]
            isOneToOne: false
            referencedRelation: "partner_interactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_attachments_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_attachments_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "partner_attachments_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_attachments_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_attachments_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      partner_cards: {
        Row: {
          board_item_id: string
          created_at: string
          created_by: string | null
          id: string
          link_role: string
          notes: string | null
          partner_entity_id: string
          updated_at: string
        }
        Insert: {
          board_item_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          link_role?: string
          notes?: string | null
          partner_entity_id: string
          updated_at?: string
        }
        Update: {
          board_item_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          link_role?: string
          notes?: string | null
          partner_entity_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "partner_cards_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_cards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_cards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "partner_cards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_cards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_cards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_cards_partner_entity_id_fkey"
            columns: ["partner_entity_id"]
            isOneToOne: false
            referencedRelation: "partner_entities"
            referencedColumns: ["id"]
          },
        ]
      }
      partner_chapters: {
        Row: {
          chapter_code: string
          chapter_name: string
          created_at: string | null
          id: string
          is_active: boolean | null
          partnership_end: string | null
          partnership_start: string | null
        }
        Insert: {
          chapter_code: string
          chapter_name: string
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          partnership_end?: string | null
          partnership_start?: string | null
        }
        Update: {
          chapter_code?: string
          chapter_name?: string
          created_at?: string | null
          id?: string
          is_active?: boolean | null
          partnership_end?: string | null
          partnership_start?: string | null
        }
        Relationships: []
      }
      partner_entities: {
        Row: {
          chapter: string | null
          contact_email: string | null
          contact_name: string | null
          created_at: string | null
          cycle_code: string | null
          description: string | null
          entity_type: string
          follow_up_date: string | null
          id: string
          last_interaction_at: string | null
          mou_stage: string | null
          name: string
          next_action: string | null
          notes: string | null
          organization_id: string
          partnership_date: string
          status: string | null
          updated_at: string | null
        }
        Insert: {
          chapter?: string | null
          contact_email?: string | null
          contact_name?: string | null
          created_at?: string | null
          cycle_code?: string | null
          description?: string | null
          entity_type: string
          follow_up_date?: string | null
          id?: string
          last_interaction_at?: string | null
          mou_stage?: string | null
          name: string
          next_action?: string | null
          notes?: string | null
          organization_id?: string
          partnership_date: string
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          chapter?: string | null
          contact_email?: string | null
          contact_name?: string | null
          created_at?: string | null
          cycle_code?: string | null
          description?: string | null
          entity_type?: string
          follow_up_date?: string | null
          id?: string
          last_interaction_at?: string | null
          mou_stage?: string | null
          name?: string
          next_action?: string | null
          notes?: string | null
          organization_id?: string
          partnership_date?: string
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "partner_entities_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      partner_interactions: {
        Row: {
          actor_member_id: string | null
          created_at: string | null
          details: string | null
          follow_up_date: string | null
          id: string
          interaction_type: string
          next_action: string | null
          outcome: string | null
          partner_id: string
          summary: string
        }
        Insert: {
          actor_member_id?: string | null
          created_at?: string | null
          details?: string | null
          follow_up_date?: string | null
          id?: string
          interaction_type: string
          next_action?: string | null
          outcome?: string | null
          partner_id: string
          summary: string
        }
        Update: {
          actor_member_id?: string | null
          created_at?: string | null
          details?: string | null
          follow_up_date?: string | null
          id?: string
          interaction_type?: string
          next_action?: string | null
          outcome?: string | null
          partner_id?: string
          summary?: string
        }
        Relationships: [
          {
            foreignKeyName: "partner_interactions_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_interactions_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "partner_interactions_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_interactions_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_interactions_actor_member_id_fkey"
            columns: ["actor_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partner_interactions_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "partner_entities"
            referencedColumns: ["id"]
          },
        ]
      }
      pending_manual_version_approvals: {
        Row: {
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          expires_at: string
          governance_document_id: string | null
          id: string
          notes: string | null
          proposed_at: string
          proposed_by: string
          signoff_at: string | null
          signoff_member_id: string | null
          status: string
          updated_at: string
          version_label: string
        }
        Insert: {
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          expires_at?: string
          governance_document_id?: string | null
          id?: string
          notes?: string | null
          proposed_at?: string
          proposed_by: string
          signoff_at?: string | null
          signoff_member_id?: string | null
          status?: string
          updated_at?: string
          version_label: string
        }
        Update: {
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          expires_at?: string
          governance_document_id?: string | null
          id?: string
          notes?: string | null
          proposed_at?: string
          proposed_by?: string
          signoff_at?: string | null
          signoff_member_id?: string | null
          status?: string
          updated_at?: string
          version_label?: string
        }
        Relationships: [
          {
            foreignKeyName: "pending_manual_version_approvals_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_governance_document_id_fkey"
            columns: ["governance_document_id"]
            isOneToOne: false
            referencedRelation: "governance_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_signoff_member_id_fkey"
            columns: ["signoff_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_signoff_member_id_fkey"
            columns: ["signoff_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_signoff_member_id_fkey"
            columns: ["signoff_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_signoff_member_id_fkey"
            columns: ["signoff_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_manual_version_approvals_signoff_member_id_fkey"
            columns: ["signoff_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      persons: {
        Row: {
          address: string | null
          anonymized_at: string | null
          auth_id: string | null
          birth_date: string | null
          city: string | null
          consent_accepted_at: string | null
          consent_status: string
          consent_version: string | null
          country: string | null
          created_at: string
          credly_badges: Json | null
          credly_url: string | null
          credly_verified_at: string | null
          email: string
          id: string
          legacy_member_id: string | null
          linkedin_url: string | null
          name: string
          organization_id: string
          phone: string | null
          photo_url: string | null
          pmi_id: string | null
          secondary_emails: string[]
          share_address: boolean
          share_birth_date: boolean
          share_whatsapp: boolean
          state: string | null
          updated_at: string
        }
        Insert: {
          address?: string | null
          anonymized_at?: string | null
          auth_id?: string | null
          birth_date?: string | null
          city?: string | null
          consent_accepted_at?: string | null
          consent_status?: string
          consent_version?: string | null
          country?: string | null
          created_at?: string
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          email: string
          id?: string
          legacy_member_id?: string | null
          linkedin_url?: string | null
          name: string
          organization_id?: string
          phone?: string | null
          photo_url?: string | null
          pmi_id?: string | null
          secondary_emails?: string[]
          share_address?: boolean
          share_birth_date?: boolean
          share_whatsapp?: boolean
          state?: string | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          anonymized_at?: string | null
          auth_id?: string | null
          birth_date?: string | null
          city?: string | null
          consent_accepted_at?: string | null
          consent_status?: string
          consent_version?: string | null
          country?: string | null
          created_at?: string
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          email?: string
          id?: string
          legacy_member_id?: string | null
          linkedin_url?: string | null
          name?: string
          organization_id?: string
          phone?: string | null
          photo_url?: string | null
          pmi_id?: string | null
          secondary_emails?: string[]
          share_address?: boolean
          share_birth_date?: boolean
          share_whatsapp?: boolean
          state?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "persons_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      pii_access_log: {
        Row: {
          accessed_at: string
          accessor_id: string | null
          context: string
          fields_accessed: string[]
          id: string
          reason: string | null
          target_member_id: string | null
        }
        Insert: {
          accessed_at?: string
          accessor_id?: string | null
          context: string
          fields_accessed: string[]
          id?: string
          reason?: string | null
          target_member_id?: string | null
        }
        Update: {
          accessed_at?: string
          accessor_id?: string | null
          context?: string
          fields_accessed?: string[]
          id?: string
          reason?: string | null
          target_member_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pii_access_log_accessor_id_fkey"
            columns: ["accessor_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pii_access_log_accessor_id_fkey"
            columns: ["accessor_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "pii_access_log_accessor_id_fkey"
            columns: ["accessor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pii_access_log_accessor_id_fkey"
            columns: ["accessor_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pii_access_log_accessor_id_fkey"
            columns: ["accessor_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pii_access_log_target_member_id_fkey"
            columns: ["target_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pii_access_log_target_member_id_fkey"
            columns: ["target_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "pii_access_log_target_member_id_fkey"
            columns: ["target_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pii_access_log_target_member_id_fkey"
            columns: ["target_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pii_access_log_target_member_id_fkey"
            columns: ["target_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      pilots: {
        Row: {
          board_id: string | null
          completed_at: string | null
          created_at: string | null
          created_by: string | null
          hypothesis: string | null
          id: string
          initiative_id: string | null
          lessons_learned: Json | null
          one_pager_md: string | null
          organization_id: string
          pilot_number: number
          problem_statement: string | null
          scope: string | null
          started_at: string | null
          status: string
          success_metrics: Json | null
          team_member_ids: string[] | null
          title: string
          updated_at: string | null
        }
        Insert: {
          board_id?: string | null
          completed_at?: string | null
          created_at?: string | null
          created_by?: string | null
          hypothesis?: string | null
          id?: string
          initiative_id?: string | null
          lessons_learned?: Json | null
          one_pager_md?: string | null
          organization_id?: string
          pilot_number: number
          problem_statement?: string | null
          scope?: string | null
          started_at?: string | null
          status?: string
          success_metrics?: Json | null
          team_member_ids?: string[] | null
          title: string
          updated_at?: string | null
        }
        Update: {
          board_id?: string | null
          completed_at?: string | null
          created_at?: string | null
          created_by?: string | null
          hypothesis?: string | null
          id?: string
          initiative_id?: string | null
          lessons_learned?: Json | null
          one_pager_md?: string | null
          organization_id?: string
          pilot_number?: number
          problem_statement?: string | null
          scope?: string | null
          started_at?: string | null
          status?: string
          success_metrics?: Json | null
          team_member_ids?: string[] | null
          title?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pilots_board_id_fkey"
            columns: ["board_id"]
            isOneToOne: false
            referencedRelation: "project_boards"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pilots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pilots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "pilots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pilots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pilots_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pilots_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pilots_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      platform_settings: {
        Row: {
          change_reason: string | null
          changed_at: string | null
          changed_by: string | null
          description: string | null
          key: string
          value: Json
        }
        Insert: {
          change_reason?: string | null
          changed_at?: string | null
          changed_by?: string | null
          description?: string | null
          key: string
          value: Json
        }
        Update: {
          change_reason?: string | null
          changed_at?: string | null
          changed_by?: string | null
          description?: string | null
          key?: string
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "platform_settings_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_settings_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "platform_settings_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_settings_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "platform_settings_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      pmi_video_screenings: {
        Row: {
          application_id: string
          created_at: string
          drive_file_id: string | null
          drive_file_name: string | null
          drive_folder_id: string | null
          duration_seconds: number | null
          failure_reason: string | null
          file_size_bytes: number | null
          id: string
          mime_type: string | null
          organization_id: string
          pillar: string
          question_index: number
          question_text: string
          retry_count: number
          status: string
          storage_provider: string
          transcription: string | null
          transcription_at: string | null
          transcription_confidence: number | null
          transcription_model_version: string | null
          transcription_provider: string | null
          updated_at: string
          uploaded_at: string | null
          youtube_url: string | null
        }
        Insert: {
          application_id: string
          created_at?: string
          drive_file_id?: string | null
          drive_file_name?: string | null
          drive_folder_id?: string | null
          duration_seconds?: number | null
          failure_reason?: string | null
          file_size_bytes?: number | null
          id?: string
          mime_type?: string | null
          organization_id?: string
          pillar: string
          question_index: number
          question_text: string
          retry_count?: number
          status?: string
          storage_provider: string
          transcription?: string | null
          transcription_at?: string | null
          transcription_confidence?: number | null
          transcription_model_version?: string | null
          transcription_provider?: string | null
          updated_at?: string
          uploaded_at?: string | null
          youtube_url?: string | null
        }
        Update: {
          application_id?: string
          created_at?: string
          drive_file_id?: string | null
          drive_file_name?: string | null
          drive_folder_id?: string | null
          duration_seconds?: number | null
          failure_reason?: string | null
          file_size_bytes?: number | null
          id?: string
          mime_type?: string | null
          organization_id?: string
          pillar?: string
          question_index?: number
          question_text?: string
          retry_count?: number
          status?: string
          storage_provider?: string
          transcription?: string | null
          transcription_at?: string | null
          transcription_confidence?: number | null
          transcription_model_version?: string | null
          transcription_provider?: string | null
          updated_at?: string
          uploaded_at?: string | null
          youtube_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pmi_video_screenings_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      portfolio_kpi_quarterly_targets: {
        Row: {
          id: string
          kpi_target_id: string
          notes: string | null
          organization_id: string
          quarter: number
          quarter_cumulative_target: number
          quarter_target: number
        }
        Insert: {
          id?: string
          kpi_target_id: string
          notes?: string | null
          organization_id?: string
          quarter: number
          quarter_cumulative_target: number
          quarter_target: number
        }
        Update: {
          id?: string
          kpi_target_id?: string
          notes?: string | null
          organization_id?: string
          quarter?: number
          quarter_cumulative_target?: number
          quarter_target?: number
        }
        Relationships: [
          {
            foreignKeyName: "portfolio_kpi_quarterly_targets_kpi_target_id_fkey"
            columns: ["kpi_target_id"]
            isOneToOne: false
            referencedRelation: "portfolio_kpi_targets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "portfolio_kpi_quarterly_targets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      portfolio_kpi_targets: {
        Row: {
          created_at: string | null
          critical_threshold: number
          cycle_code: string
          display_order: number | null
          id: string
          metric_key: string
          metric_label: Json
          organization_id: string
          source_query: string | null
          target_value: number
          unit: string | null
          warning_threshold: number
        }
        Insert: {
          created_at?: string | null
          critical_threshold: number
          cycle_code?: string
          display_order?: number | null
          id?: string
          metric_key: string
          metric_label: Json
          organization_id?: string
          source_query?: string | null
          target_value: number
          unit?: string | null
          warning_threshold: number
        }
        Update: {
          created_at?: string | null
          critical_threshold?: number
          cycle_code?: string
          display_order?: number | null
          id?: string
          metric_key?: string
          metric_label?: Json
          organization_id?: string
          source_query?: string | null
          target_value?: number
          unit?: string | null
          warning_threshold?: number
        }
        Relationships: [
          {
            foreignKeyName: "portfolio_kpi_targets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      preview_gate_eligibles_cache: {
        Row: {
          doc_type: string
          eligible_gates: string[]
          last_refreshed: string
          member_id: string
        }
        Insert: {
          doc_type: string
          eligible_gates?: string[]
          last_refreshed?: string
          member_id: string
        }
        Update: {
          doc_type?: string
          eligible_gates?: string[]
          last_refreshed?: string
          member_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "preview_gate_eligibles_cache_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preview_gate_eligibles_cache_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "preview_gate_eligibles_cache_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preview_gate_eligibles_cache_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "preview_gate_eligibles_cache_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      privacy_policy_versions: {
        Row: {
          change_request_id: string | null
          created_at: string | null
          created_by: string | null
          effective_at: string
          id: string
          notification_campaign_id: string | null
          notification_created_at: string | null
          summary_en: string | null
          summary_es: string | null
          summary_pt: string | null
          version: string
        }
        Insert: {
          change_request_id?: string | null
          created_at?: string | null
          created_by?: string | null
          effective_at?: string
          id?: string
          notification_campaign_id?: string | null
          notification_created_at?: string | null
          summary_en?: string | null
          summary_es?: string | null
          summary_pt?: string | null
          version: string
        }
        Update: {
          change_request_id?: string | null
          created_at?: string | null
          created_by?: string | null
          effective_at?: string
          id?: string
          notification_campaign_id?: string | null
          notification_created_at?: string | null
          summary_en?: string | null
          summary_es?: string | null
          summary_pt?: string | null
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "privacy_policy_versions_change_request_id_fkey"
            columns: ["change_request_id"]
            isOneToOne: false
            referencedRelation: "change_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      program_risks: {
        Row: {
          artia_activity_id: number | null
          artia_synced_at: string | null
          cause: string
          consequence: string
          created_at: string
          cycle_year: number
          id: string
          impact: string | null
          probability: string | null
          responsible_role: string | null
          risk_code: string
          risk_title: string
          status: string
          treatment: string
          updated_at: string
        }
        Insert: {
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          cause: string
          consequence: string
          created_at?: string
          cycle_year?: number
          id?: string
          impact?: string | null
          probability?: string | null
          responsible_role?: string | null
          risk_code: string
          risk_title: string
          status?: string
          treatment: string
          updated_at?: string
        }
        Update: {
          artia_activity_id?: number | null
          artia_synced_at?: string | null
          cause?: string
          consequence?: string
          created_at?: string
          cycle_year?: number
          id?: string
          impact?: string | null
          probability?: string | null
          responsible_role?: string | null
          risk_code?: string
          risk_title?: string
          status?: string
          treatment?: string
          updated_at?: string
        }
        Relationships: []
      }
      project_boards: {
        Row: {
          board_name: string
          board_scope: string
          columns: Json
          created_at: string
          created_by: string | null
          cycle_scope: string | null
          domain_key: string | null
          id: string
          initiative_id: string | null
          is_active: boolean
          organization_id: string
          source: string
          updated_at: string
        }
        Insert: {
          board_name: string
          board_scope?: string
          columns?: Json
          created_at?: string
          created_by?: string | null
          cycle_scope?: string | null
          domain_key?: string | null
          id?: string
          initiative_id?: string | null
          is_active?: boolean
          organization_id?: string
          source?: string
          updated_at?: string
        }
        Update: {
          board_name?: string
          board_scope?: string
          columns?: Json
          created_at?: string
          created_by?: string | null
          cycle_scope?: string | null
          domain_key?: string | null
          id?: string
          initiative_id?: string | null
          is_active?: boolean
          organization_id?: string
          source?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_boards_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_boards_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_boards_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      project_memberships: {
        Row: {
          created_at: string
          cycle_code: string
          id: string
          is_active: boolean
          member_id: string
          metadata: Json
          notes: string | null
          organization_id: string
          project_name: string
          project_type: string
          role: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          cycle_code: string
          id?: string
          is_active?: boolean
          member_id: string
          metadata?: Json
          notes?: string | null
          organization_id?: string
          project_name: string
          project_type?: string
          role?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          cycle_code?: string
          id?: string
          is_active?: boolean
          member_id?: string
          metadata?: Json
          notes?: string | null
          organization_id?: string
          project_name?: string
          project_type?: string
          role?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_memberships_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_memberships_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "project_memberships_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_memberships_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_memberships_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "project_memberships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      public_publications: {
        Row: {
          abstract: string | null
          author_member_ids: string[] | null
          authors: string[]
          board_item_id: string | null
          citation_count: number | null
          created_at: string | null
          cycle_code: string | null
          doi: string | null
          external_platform: string | null
          external_url: string | null
          id: string
          initiative_id: string | null
          is_featured: boolean | null
          is_published: boolean | null
          keywords: string[] | null
          language: string | null
          organization_id: string
          pdf_url: string | null
          publication_date: string | null
          publication_type: string
          source_idea_id: string | null
          thumbnail_url: string | null
          title: string
          updated_at: string | null
          view_count: number | null
        }
        Insert: {
          abstract?: string | null
          author_member_ids?: string[] | null
          authors: string[]
          board_item_id?: string | null
          citation_count?: number | null
          created_at?: string | null
          cycle_code?: string | null
          doi?: string | null
          external_platform?: string | null
          external_url?: string | null
          id?: string
          initiative_id?: string | null
          is_featured?: boolean | null
          is_published?: boolean | null
          keywords?: string[] | null
          language?: string | null
          organization_id?: string
          pdf_url?: string | null
          publication_date?: string | null
          publication_type?: string
          source_idea_id?: string | null
          thumbnail_url?: string | null
          title: string
          updated_at?: string | null
          view_count?: number | null
        }
        Update: {
          abstract?: string | null
          author_member_ids?: string[] | null
          authors?: string[]
          board_item_id?: string | null
          citation_count?: number | null
          created_at?: string | null
          cycle_code?: string | null
          doi?: string | null
          external_platform?: string | null
          external_url?: string | null
          id?: string
          initiative_id?: string | null
          is_featured?: boolean | null
          is_published?: boolean | null
          keywords?: string[] | null
          language?: string | null
          organization_id?: string
          pdf_url?: string | null
          publication_date?: string | null
          publication_type?: string
          source_idea_id?: string | null
          thumbnail_url?: string | null
          title?: string
          updated_at?: string | null
          view_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "public_publications_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "public_publications_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "public_publications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "public_publications_source_idea_id_fkey"
            columns: ["source_idea_id"]
            isOneToOne: false
            referencedRelation: "publication_ideas"
            referencedColumns: ["id"]
          },
        ]
      }
      publication_ideas: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          archived_reason: string | null
          author_ids: string[] | null
          created_at: string
          id: string
          initiative_id: string | null
          metadata: Json
          organization_id: string
          proposed_channels: string[] | null
          proposer_member_id: string
          published_at: string | null
          rejection_reason: string | null
          review_sub_stage: string | null
          series_id: string | null
          series_position: number | null
          source_id: string | null
          source_type: string | null
          stage: string
          summary: string | null
          target_languages: string[]
          themes: string[] | null
          title: string
          tribe_id: number | null
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          archived_reason?: string | null
          author_ids?: string[] | null
          created_at?: string
          id?: string
          initiative_id?: string | null
          metadata?: Json
          organization_id?: string
          proposed_channels?: string[] | null
          proposer_member_id: string
          published_at?: string | null
          rejection_reason?: string | null
          review_sub_stage?: string | null
          series_id?: string | null
          series_position?: number | null
          source_id?: string | null
          source_type?: string | null
          stage?: string
          summary?: string | null
          target_languages?: string[]
          themes?: string[] | null
          title: string
          tribe_id?: number | null
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          archived_reason?: string | null
          author_ids?: string[] | null
          created_at?: string
          id?: string
          initiative_id?: string | null
          metadata?: Json
          organization_id?: string
          proposed_channels?: string[] | null
          proposer_member_id?: string
          published_at?: string | null
          rejection_reason?: string | null
          review_sub_stage?: string | null
          series_id?: string | null
          series_position?: number | null
          source_id?: string | null
          source_type?: string | null
          stage?: string
          summary?: string | null
          target_languages?: string[]
          themes?: string[] | null
          title?: string
          tribe_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "publication_ideas_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_ideas_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_ideas_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_ideas_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "publication_series"
            referencedColumns: ["id"]
          },
        ]
      }
      publication_series: {
        Row: {
          cadence_hint: string | null
          cover_image_url: string | null
          created_at: string
          created_by: string | null
          description_i18n: Json | null
          editorial_voice: string | null
          format_default: string | null
          hero_initiative_id: string | null
          hero_tribe_id: number | null
          id: string
          is_active: boolean | null
          organization_id: string
          slug: string
          target_audience: string | null
          title_i18n: Json
          updated_at: string
        }
        Insert: {
          cadence_hint?: string | null
          cover_image_url?: string | null
          created_at?: string
          created_by?: string | null
          description_i18n?: Json | null
          editorial_voice?: string | null
          format_default?: string | null
          hero_initiative_id?: string | null
          hero_tribe_id?: number | null
          id?: string
          is_active?: boolean | null
          organization_id?: string
          slug: string
          target_audience?: string | null
          title_i18n: Json
          updated_at?: string
        }
        Update: {
          cadence_hint?: string | null
          cover_image_url?: string | null
          created_at?: string
          created_by?: string | null
          description_i18n?: Json | null
          editorial_voice?: string | null
          format_default?: string | null
          hero_initiative_id?: string | null
          hero_tribe_id?: number | null
          id?: string
          is_active?: boolean | null
          organization_id?: string
          slug?: string
          target_audience?: string | null
          title_i18n?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "publication_series_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_series_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_series_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_series_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_series_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_series_hero_initiative_id_fkey"
            columns: ["hero_initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_series_hero_tribe_id_fkey"
            columns: ["hero_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      publication_submission_authors: {
        Row: {
          author_order: number
          created_at: string | null
          id: string
          is_corresponding: boolean | null
          member_id: string
          submission_id: string
        }
        Insert: {
          author_order?: number
          created_at?: string | null
          id?: string
          is_corresponding?: boolean | null
          member_id: string
          submission_id: string
        }
        Update: {
          author_order?: number
          created_at?: string | null
          id?: string
          is_corresponding?: boolean | null
          member_id?: string
          submission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "publication_submission_authors_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_authors_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_submission_authors_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_authors_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_authors_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_authors_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "publication_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      publication_submission_events: {
        Row: {
          board_item_id: string
          channel: string
          created_at: string
          external_link: string | null
          id: number
          notes: string | null
          outcome: string
          published_at: string | null
          submitted_at: string | null
          updated_at: string
          updated_by: string
        }
        Insert: {
          board_item_id: string
          channel?: string
          created_at?: string
          external_link?: string | null
          id?: never
          notes?: string | null
          outcome?: string
          published_at?: string | null
          submitted_at?: string | null
          updated_at?: string
          updated_by: string
        }
        Update: {
          board_item_id?: string
          channel?: string
          created_at?: string
          external_link?: string | null
          id?: never
          notes?: string | null
          outcome?: string
          published_at?: string | null
          submitted_at?: string | null
          updated_at?: string
          updated_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "publication_submission_events_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submission_events_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      publication_submissions: {
        Row: {
          abstract: string | null
          acceptance_date: string | null
          actual_cost_brl: number | null
          board_item_id: string | null
          cost_paid_by: string | null
          created_at: string | null
          created_by: string | null
          doi_or_url: string | null
          estimated_cost_brl: number | null
          id: string
          initiative_id: string | null
          legacy_tribe_key: string | null
          organization_id: string
          presentation_date: string | null
          primary_author_id: string
          review_deadline: string | null
          reviewer_feedback: string | null
          source_idea_id: string | null
          status: Database["public"]["Enums"]["submission_status"]
          submission_date: string | null
          target_name: string
          target_type: Database["public"]["Enums"]["submission_target_type"]
          target_url: string | null
          title: string
          updated_at: string | null
        }
        Insert: {
          abstract?: string | null
          acceptance_date?: string | null
          actual_cost_brl?: number | null
          board_item_id?: string | null
          cost_paid_by?: string | null
          created_at?: string | null
          created_by?: string | null
          doi_or_url?: string | null
          estimated_cost_brl?: number | null
          id?: string
          initiative_id?: string | null
          legacy_tribe_key?: string | null
          organization_id?: string
          presentation_date?: string | null
          primary_author_id: string
          review_deadline?: string | null
          reviewer_feedback?: string | null
          source_idea_id?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          submission_date?: string | null
          target_name: string
          target_type: Database["public"]["Enums"]["submission_target_type"]
          target_url?: string | null
          title: string
          updated_at?: string | null
        }
        Update: {
          abstract?: string | null
          acceptance_date?: string | null
          actual_cost_brl?: number | null
          board_item_id?: string | null
          cost_paid_by?: string | null
          created_at?: string | null
          created_by?: string | null
          doi_or_url?: string | null
          estimated_cost_brl?: number | null
          id?: string
          initiative_id?: string | null
          legacy_tribe_key?: string | null
          organization_id?: string
          presentation_date?: string | null
          primary_author_id?: string
          review_deadline?: string | null
          reviewer_feedback?: string | null
          source_idea_id?: string | null
          status?: Database["public"]["Enums"]["submission_status"]
          submission_date?: string | null
          target_name?: string
          target_type?: Database["public"]["Enums"]["submission_target_type"]
          target_url?: string | null
          title?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "publication_submissions_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_submissions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_primary_author_id_fkey"
            columns: ["primary_author_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_primary_author_id_fkey"
            columns: ["primary_author_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "publication_submissions_primary_author_id_fkey"
            columns: ["primary_author_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_primary_author_id_fkey"
            columns: ["primary_author_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_primary_author_id_fkey"
            columns: ["primary_author_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "publication_submissions_source_idea_id_fkey"
            columns: ["source_idea_id"]
            isOneToOne: false
            referencedRelation: "publication_ideas"
            referencedColumns: ["id"]
          },
        ]
      }
      quadrants: {
        Row: {
          color: string
          created_at: string | null
          description_en: string | null
          description_es: string | null
          description_pt: string | null
          display_order: number
          id: number
          is_active: boolean | null
          key: string
          name_en: string
          name_es: string
          name_pt: string
        }
        Insert: {
          color?: string
          created_at?: string | null
          description_en?: string | null
          description_es?: string | null
          description_pt?: string | null
          display_order?: number
          id: number
          is_active?: boolean | null
          key: string
          name_en: string
          name_es: string
          name_pt: string
        }
        Update: {
          color?: string
          created_at?: string | null
          description_en?: string | null
          description_es?: string | null
          description_pt?: string | null
          display_order?: number
          id?: number
          is_active?: boolean | null
          key?: string
          name_en?: string
          name_es?: string
          name_pt?: string
        }
        Relationships: []
      }
      re_engagement_pipeline: {
        Row: {
          cancellation_reason: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          cycle_code: string
          id: string
          invitation_message: string | null
          invited_at: string | null
          invited_by: string | null
          member_id: string
          metadata: Json | null
          reason_category_snapshot: string | null
          responded_at: string | null
          response: string | null
          response_note: string | null
          return_interest_snapshot: boolean | null
          staged_at: string
          staged_by: string | null
          staged_source: string
          state: Database["public"]["Enums"]["re_engagement_state"]
          updated_at: string
        }
        Insert: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          cycle_code: string
          id?: string
          invitation_message?: string | null
          invited_at?: string | null
          invited_by?: string | null
          member_id: string
          metadata?: Json | null
          reason_category_snapshot?: string | null
          responded_at?: string | null
          response?: string | null
          response_note?: string | null
          return_interest_snapshot?: boolean | null
          staged_at?: string
          staged_by?: string | null
          staged_source: string
          state?: Database["public"]["Enums"]["re_engagement_state"]
          updated_at?: string
        }
        Update: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          cycle_code?: string
          id?: string
          invitation_message?: string | null
          invited_at?: string | null
          invited_by?: string | null
          member_id?: string
          metadata?: Json | null
          reason_category_snapshot?: string | null
          responded_at?: string | null
          response?: string | null
          response_note?: string | null
          return_interest_snapshot?: boolean | null
          staged_at?: string
          staged_by?: string | null
          staged_source?: string
          state?: Database["public"]["Enums"]["re_engagement_state"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "re_engagement_pipeline_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_cycle_code_fkey"
            columns: ["cycle_code"]
            isOneToOne: false
            referencedRelation: "cycles"
            referencedColumns: ["cycle_code"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_staged_by_fkey"
            columns: ["staged_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_staged_by_fkey"
            columns: ["staged_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_staged_by_fkey"
            columns: ["staged_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_staged_by_fkey"
            columns: ["staged_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "re_engagement_pipeline_staged_by_fkey"
            columns: ["staged_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      release_items: {
        Row: {
          category: string
          created_at: string
          description_en: string | null
          description_es: string | null
          description_pt: string | null
          gc_reference: string | null
          icon: string | null
          id: string
          release_id: string
          sort_order: number
          title_en: string | null
          title_es: string | null
          title_pt: string
          visible: boolean
        }
        Insert: {
          category?: string
          created_at?: string
          description_en?: string | null
          description_es?: string | null
          description_pt?: string | null
          gc_reference?: string | null
          icon?: string | null
          id?: string
          release_id: string
          sort_order?: number
          title_en?: string | null
          title_es?: string | null
          title_pt: string
          visible?: boolean
        }
        Update: {
          category?: string
          created_at?: string
          description_en?: string | null
          description_es?: string | null
          description_pt?: string | null
          gc_reference?: string | null
          icon?: string | null
          id?: string
          release_id?: string
          sort_order?: number
          title_en?: string | null
          title_es?: string | null
          title_pt?: string
          visible?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "release_items_release_id_fkey"
            columns: ["release_id"]
            isOneToOne: false
            referencedRelation: "releases"
            referencedColumns: ["id"]
          },
        ]
      }
      release_readiness_policies: {
        Row: {
          max_open_warnings: number
          mode: string
          policy_key: string
          require_fresh_snapshot_hours: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          max_open_warnings?: number
          mode: string
          policy_key: string
          require_fresh_snapshot_hours?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          max_open_warnings?: number
          mode?: string
          policy_key?: string
          require_fresh_snapshot_hours?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "release_readiness_policies_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      releases: {
        Row: {
          created_at: string | null
          created_by: string | null
          description: string | null
          git_sha: string | null
          git_tag: string | null
          id: string
          is_current: boolean | null
          release_type: string
          released_at: string | null
          stats: Json | null
          title: string
          version: string
          waves_included: string[] | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          git_sha?: string | null
          git_tag?: string | null
          id?: string
          is_current?: boolean | null
          release_type?: string
          released_at?: string | null
          stats?: Json | null
          title: string
          version: string
          waves_included?: string[] | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          git_sha?: string | null
          git_tag?: string | null
          id?: string
          is_current?: boolean | null
          release_type?: string
          released_at?: string | null
          stats?: Json | null
          title?: string
          version?: string
          waves_included?: string[] | null
        }
        Relationships: [
          {
            foreignKeyName: "releases_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "releases_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "releases_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "releases_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "releases_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      revenue_categories: {
        Row: {
          created_at: string | null
          description: string | null
          display_order: number | null
          id: string
          name: string
          value_type: string
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          id?: string
          name: string
          value_type?: string
        }
        Update: {
          created_at?: string | null
          description?: string | null
          display_order?: number | null
          id?: string
          name?: string
          value_type?: string
        }
        Relationships: []
      }
      revenue_entries: {
        Row: {
          amount_brl: number | null
          category_id: string
          created_at: string | null
          created_by: string | null
          date: string
          description: string
          id: string
          notes: string | null
          organization_id: string | null
          updated_at: string | null
          value_type: string
        }
        Insert: {
          amount_brl?: number | null
          category_id: string
          created_at?: string | null
          created_by?: string | null
          date: string
          description: string
          id?: string
          notes?: string | null
          organization_id?: string | null
          updated_at?: string | null
          value_type?: string
        }
        Update: {
          amount_brl?: number | null
          category_id?: string
          created_at?: string | null
          created_by?: string | null
          date?: string
          description?: string
          id?: string
          notes?: string | null
          organization_id?: string | null
          updated_at?: string | null
          value_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "revenue_entries_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "revenue_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "revenue_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_entries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "revenue_entries_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      risk_simulations: {
        Row: {
          created_at: string | null
          id: string
          project_name: string | null
          simulation_data: Json | null
          simulation_id: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          project_name?: string | null
          simulation_data?: Json | null
          simulation_id?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          project_name?: string | null
          simulation_data?: Json | null
          simulation_id?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      selection_application_service_history: {
        Row: {
          application_id: string
          captured_at: string
          chapter_name: string
          created_at: string
          end_date: string | null
          id: string
          organization_id: string | null
          role_name: string | null
          source: string
          start_date: string | null
        }
        Insert: {
          application_id: string
          captured_at?: string
          chapter_name: string
          created_at?: string
          end_date?: string | null
          id?: string
          organization_id?: string | null
          role_name?: string | null
          source: string
          start_date?: string | null
        }
        Update: {
          application_id?: string
          captured_at?: string
          chapter_name?: string
          created_at?: string
          end_date?: string | null
          id?: string
          organization_id?: string | null
          role_name?: string | null
          source?: string
          start_date?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_application_service_history_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_application_service_history_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_applications: {
        Row: {
          academic_background: string | null
          age_band: string | null
          ai_analysis: Json | null
          ai_pm_focus_tags: string[] | null
          ai_triage_at: string | null
          ai_triage_confidence: string | null
          ai_triage_model: string | null
          ai_triage_reasoning: string | null
          ai_triage_score: number | null
          applicant_city: string | null
          applicant_name: string
          application_count: number | null
          application_date: string | null
          areas_of_interest: string | null
          availability_declared: string | null
          certifications: string | null
          chapter: string | null
          chapter_affiliation: string | null
          community_profile_private: boolean | null
          consent_ai_analysis_at: string | null
          consent_ai_analysis_revoked_at: string | null
          consent_record_id: string | null
          consent_version: string | null
          consent_voice_biometric_at: string | null
          consent_voice_biometric_evidence: string | null
          consent_voice_biometric_revoked_at: string | null
          conversion_reason: string | null
          converted_from: string | null
          converted_to: string | null
          country: string | null
          created_at: string | null
          credly_url: string | null
          cv_extracted_text: string | null
          cycle_decision_date: string | null
          cycle_id: string
          email: string
          enrichment_count: number
          feedback: string | null
          final_score: number | null
          first_name: string | null
          gender: string | null
          id: string
          imported_at: string | null
          industry: string | null
          interview_reschedule_last_nudged_at: string | null
          interview_reschedule_reason: string | null
          interview_reschedule_requested_at: string | null
          interview_reschedule_requested_by: string | null
          interview_score: number | null
          interview_status: string
          is_open_to_volunteer: boolean | null
          is_returning_member: boolean | null
          last_briefing_at: string | null
          last_briefing_jsonb: Json | null
          last_briefing_model: string | null
          last_enrichment_at: string | null
          last_enrichment_content_hash: string | null
          last_name: string | null
          leader_extra_pert_score: number | null
          leader_score: number | null
          leadership_experience: string | null
          linked_application_id: string | null
          linkedin_relevant_posts: string[] | null
          linkedin_url: string | null
          membership_status: string | null
          motivation_letter: string | null
          non_pmi_experience: string | null
          objective_score_avg: number | null
          organization_id: string
          pert_band_lower: number | null
          pert_band_upper: number | null
          pert_calc_at: string | null
          pert_cohort_n: number | null
          pert_cutoff_method: string | null
          pert_target_score: number | null
          phone: string | null
          pmi_data_fetched_at: string | null
          pmi_id: string | null
          pmi_memberships: Json | null
          previous_cycles: string[] | null
          profile_about_me: string | null
          profile_certifications: string[] | null
          profile_city: string | null
          profile_company: string | null
          profile_country: string | null
          profile_designation: string | null
          profile_industry: string | null
          profile_linkedin_url: string | null
          profile_location: string | null
          profile_specialties: string | null
          profile_state: string | null
          profile_volunteer_interest: string | null
          promotion_path: string | null
          proposed_theme: string | null
          rank_chapter: number | null
          rank_leader: number | null
          rank_overall: number | null
          rank_researcher: number | null
          reason_for_applying: string | null
          referral_source: string | null
          referrer_member_id: string | null
          renews_engagement_id: string | null
          research_score: number | null
          resume_storage_path: string | null
          resume_synced_at: string | null
          resume_url: string | null
          role_applied: string
          sector: string | null
          seniority_years: number | null
          service_first_start_date: string | null
          service_history_chapters: string | null
          service_history_count: number | null
          service_latest_end_date: string | null
          state: string | null
          status: string
          tags: string[] | null
          track_decided_at: string | null
          track_decided_by: string | null
          updated_at: string | null
          utm_data: Json | null
          vep_application_id: string | null
          vep_last_seen_at: string | null
          vep_opportunity_id: string | null
          vep_reconciled_at: string | null
          vep_reconciled_by: string | null
          vep_reconciled_note: string | null
          vep_status_raw: string | null
        }
        Insert: {
          academic_background?: string | null
          age_band?: string | null
          ai_analysis?: Json | null
          ai_pm_focus_tags?: string[] | null
          ai_triage_at?: string | null
          ai_triage_confidence?: string | null
          ai_triage_model?: string | null
          ai_triage_reasoning?: string | null
          ai_triage_score?: number | null
          applicant_city?: string | null
          applicant_name: string
          application_count?: number | null
          application_date?: string | null
          areas_of_interest?: string | null
          availability_declared?: string | null
          certifications?: string | null
          chapter?: string | null
          chapter_affiliation?: string | null
          community_profile_private?: boolean | null
          consent_ai_analysis_at?: string | null
          consent_ai_analysis_revoked_at?: string | null
          consent_record_id?: string | null
          consent_version?: string | null
          consent_voice_biometric_at?: string | null
          consent_voice_biometric_evidence?: string | null
          consent_voice_biometric_revoked_at?: string | null
          conversion_reason?: string | null
          converted_from?: string | null
          converted_to?: string | null
          country?: string | null
          created_at?: string | null
          credly_url?: string | null
          cv_extracted_text?: string | null
          cycle_decision_date?: string | null
          cycle_id: string
          email: string
          enrichment_count?: number
          feedback?: string | null
          final_score?: number | null
          first_name?: string | null
          gender?: string | null
          id?: string
          imported_at?: string | null
          industry?: string | null
          interview_reschedule_last_nudged_at?: string | null
          interview_reschedule_reason?: string | null
          interview_reschedule_requested_at?: string | null
          interview_reschedule_requested_by?: string | null
          interview_score?: number | null
          interview_status?: string
          is_open_to_volunteer?: boolean | null
          is_returning_member?: boolean | null
          last_briefing_at?: string | null
          last_briefing_jsonb?: Json | null
          last_briefing_model?: string | null
          last_enrichment_at?: string | null
          last_enrichment_content_hash?: string | null
          last_name?: string | null
          leader_extra_pert_score?: number | null
          leader_score?: number | null
          leadership_experience?: string | null
          linked_application_id?: string | null
          linkedin_relevant_posts?: string[] | null
          linkedin_url?: string | null
          membership_status?: string | null
          motivation_letter?: string | null
          non_pmi_experience?: string | null
          objective_score_avg?: number | null
          organization_id?: string
          pert_band_lower?: number | null
          pert_band_upper?: number | null
          pert_calc_at?: string | null
          pert_cohort_n?: number | null
          pert_cutoff_method?: string | null
          pert_target_score?: number | null
          phone?: string | null
          pmi_data_fetched_at?: string | null
          pmi_id?: string | null
          pmi_memberships?: Json | null
          previous_cycles?: string[] | null
          profile_about_me?: string | null
          profile_certifications?: string[] | null
          profile_city?: string | null
          profile_company?: string | null
          profile_country?: string | null
          profile_designation?: string | null
          profile_industry?: string | null
          profile_linkedin_url?: string | null
          profile_location?: string | null
          profile_specialties?: string | null
          profile_state?: string | null
          profile_volunteer_interest?: string | null
          promotion_path?: string | null
          proposed_theme?: string | null
          rank_chapter?: number | null
          rank_leader?: number | null
          rank_overall?: number | null
          rank_researcher?: number | null
          reason_for_applying?: string | null
          referral_source?: string | null
          referrer_member_id?: string | null
          renews_engagement_id?: string | null
          research_score?: number | null
          resume_storage_path?: string | null
          resume_synced_at?: string | null
          resume_url?: string | null
          role_applied?: string
          sector?: string | null
          seniority_years?: number | null
          service_first_start_date?: string | null
          service_history_chapters?: string | null
          service_history_count?: number | null
          service_latest_end_date?: string | null
          state?: string | null
          status?: string
          tags?: string[] | null
          track_decided_at?: string | null
          track_decided_by?: string | null
          updated_at?: string | null
          utm_data?: Json | null
          vep_application_id?: string | null
          vep_last_seen_at?: string | null
          vep_opportunity_id?: string | null
          vep_reconciled_at?: string | null
          vep_reconciled_by?: string | null
          vep_reconciled_note?: string | null
          vep_status_raw?: string | null
        }
        Update: {
          academic_background?: string | null
          age_band?: string | null
          ai_analysis?: Json | null
          ai_pm_focus_tags?: string[] | null
          ai_triage_at?: string | null
          ai_triage_confidence?: string | null
          ai_triage_model?: string | null
          ai_triage_reasoning?: string | null
          ai_triage_score?: number | null
          applicant_city?: string | null
          applicant_name?: string
          application_count?: number | null
          application_date?: string | null
          areas_of_interest?: string | null
          availability_declared?: string | null
          certifications?: string | null
          chapter?: string | null
          chapter_affiliation?: string | null
          community_profile_private?: boolean | null
          consent_ai_analysis_at?: string | null
          consent_ai_analysis_revoked_at?: string | null
          consent_record_id?: string | null
          consent_version?: string | null
          consent_voice_biometric_at?: string | null
          consent_voice_biometric_evidence?: string | null
          consent_voice_biometric_revoked_at?: string | null
          conversion_reason?: string | null
          converted_from?: string | null
          converted_to?: string | null
          country?: string | null
          created_at?: string | null
          credly_url?: string | null
          cv_extracted_text?: string | null
          cycle_decision_date?: string | null
          cycle_id?: string
          email?: string
          enrichment_count?: number
          feedback?: string | null
          final_score?: number | null
          first_name?: string | null
          gender?: string | null
          id?: string
          imported_at?: string | null
          industry?: string | null
          interview_reschedule_last_nudged_at?: string | null
          interview_reschedule_reason?: string | null
          interview_reschedule_requested_at?: string | null
          interview_reschedule_requested_by?: string | null
          interview_score?: number | null
          interview_status?: string
          is_open_to_volunteer?: boolean | null
          is_returning_member?: boolean | null
          last_briefing_at?: string | null
          last_briefing_jsonb?: Json | null
          last_briefing_model?: string | null
          last_enrichment_at?: string | null
          last_enrichment_content_hash?: string | null
          last_name?: string | null
          leader_extra_pert_score?: number | null
          leader_score?: number | null
          leadership_experience?: string | null
          linked_application_id?: string | null
          linkedin_relevant_posts?: string[] | null
          linkedin_url?: string | null
          membership_status?: string | null
          motivation_letter?: string | null
          non_pmi_experience?: string | null
          objective_score_avg?: number | null
          organization_id?: string
          pert_band_lower?: number | null
          pert_band_upper?: number | null
          pert_calc_at?: string | null
          pert_cohort_n?: number | null
          pert_cutoff_method?: string | null
          pert_target_score?: number | null
          phone?: string | null
          pmi_data_fetched_at?: string | null
          pmi_id?: string | null
          pmi_memberships?: Json | null
          previous_cycles?: string[] | null
          profile_about_me?: string | null
          profile_certifications?: string[] | null
          profile_city?: string | null
          profile_company?: string | null
          profile_country?: string | null
          profile_designation?: string | null
          profile_industry?: string | null
          profile_linkedin_url?: string | null
          profile_location?: string | null
          profile_specialties?: string | null
          profile_state?: string | null
          profile_volunteer_interest?: string | null
          promotion_path?: string | null
          proposed_theme?: string | null
          rank_chapter?: number | null
          rank_leader?: number | null
          rank_overall?: number | null
          rank_researcher?: number | null
          reason_for_applying?: string | null
          referral_source?: string | null
          referrer_member_id?: string | null
          renews_engagement_id?: string | null
          research_score?: number | null
          resume_storage_path?: string | null
          resume_synced_at?: string | null
          resume_url?: string | null
          role_applied?: string
          sector?: string | null
          seniority_years?: number | null
          service_first_start_date?: string | null
          service_history_chapters?: string | null
          service_history_count?: number | null
          service_latest_end_date?: string | null
          state?: string | null
          status?: string
          tags?: string[] | null
          track_decided_at?: string | null
          track_decided_by?: string | null
          updated_at?: string | null
          utm_data?: Json | null
          vep_application_id?: string | null
          vep_last_seen_at?: string | null
          vep_opportunity_id?: string | null
          vep_reconciled_at?: string | null
          vep_reconciled_by?: string | null
          vep_reconciled_note?: string | null
          vep_status_raw?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_applications_consent_record_id_fkey"
            columns: ["consent_record_id"]
            isOneToOne: false
            referencedRelation: "consent_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "selection_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_interview_reschedule_requested_by_fkey"
            columns: ["interview_reschedule_requested_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_interview_reschedule_requested_by_fkey"
            columns: ["interview_reschedule_requested_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_applications_interview_reschedule_requested_by_fkey"
            columns: ["interview_reschedule_requested_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_interview_reschedule_requested_by_fkey"
            columns: ["interview_reschedule_requested_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_interview_reschedule_requested_by_fkey"
            columns: ["interview_reschedule_requested_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_linked_application_id_fkey"
            columns: ["linked_application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_applications_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_renews_engagement_id_fkey"
            columns: ["renews_engagement_id"]
            isOneToOne: false
            referencedRelation: "auth_engagements"
            referencedColumns: ["engagement_id"]
          },
          {
            foreignKeyName: "selection_applications_renews_engagement_id_fkey"
            columns: ["renews_engagement_id"]
            isOneToOne: false
            referencedRelation: "engagements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_track_decided_by_fkey"
            columns: ["track_decided_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_track_decided_by_fkey"
            columns: ["track_decided_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_applications_track_decided_by_fkey"
            columns: ["track_decided_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_track_decided_by_fkey"
            columns: ["track_decided_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_track_decided_by_fkey"
            columns: ["track_decided_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_vep_reconciled_by_fkey"
            columns: ["vep_reconciled_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_vep_reconciled_by_fkey"
            columns: ["vep_reconciled_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_applications_vep_reconciled_by_fkey"
            columns: ["vep_reconciled_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_vep_reconciled_by_fkey"
            columns: ["vep_reconciled_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_applications_vep_reconciled_by_fkey"
            columns: ["vep_reconciled_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_committee: {
        Row: {
          can_interview: boolean | null
          created_at: string | null
          cycle_id: string
          id: string
          member_id: string
          organization_id: string
          role: string
        }
        Insert: {
          can_interview?: boolean | null
          created_at?: string | null
          cycle_id: string
          id?: string
          member_id: string
          organization_id?: string
          role?: string
        }
        Update: {
          can_interview?: boolean | null
          created_at?: string | null
          cycle_id?: string
          id?: string
          member_id?: string
          organization_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "selection_committee_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "selection_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_committee_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_committee_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_committee_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_committee_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_committee_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_committee_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_cycles: {
        Row: {
          close_date: string | null
          contracting_chapter: string | null
          created_at: string | null
          created_by: string | null
          cycle_code: string
          final_cutoff_formula: string | null
          id: string
          interview_booking_url: string | null
          interview_criteria: Json
          interview_questions: Json | null
          leader_extra_criteria: Json | null
          leads_auto_promoted_at: string | null
          min_evaluators: number
          objective_criteria: Json
          objective_cutoff_formula: string | null
          onboarding_steps: Json
          open_date: string | null
          organization_id: string
          phase: string
          scoring_formula: Json | null
          status: string
          title: string
          updated_at: string | null
        }
        Insert: {
          close_date?: string | null
          contracting_chapter?: string | null
          created_at?: string | null
          created_by?: string | null
          cycle_code: string
          final_cutoff_formula?: string | null
          id?: string
          interview_booking_url?: string | null
          interview_criteria?: Json
          interview_questions?: Json | null
          leader_extra_criteria?: Json | null
          leads_auto_promoted_at?: string | null
          min_evaluators?: number
          objective_criteria?: Json
          objective_cutoff_formula?: string | null
          onboarding_steps?: Json
          open_date?: string | null
          organization_id?: string
          phase?: string
          scoring_formula?: Json | null
          status?: string
          title: string
          updated_at?: string | null
        }
        Update: {
          close_date?: string | null
          contracting_chapter?: string | null
          created_at?: string | null
          created_by?: string | null
          cycle_code?: string
          final_cutoff_formula?: string | null
          id?: string
          interview_booking_url?: string | null
          interview_criteria?: Json
          interview_questions?: Json | null
          leader_extra_criteria?: Json | null
          leads_auto_promoted_at?: string | null
          min_evaluators?: number
          objective_criteria?: Json
          objective_cutoff_formula?: string | null
          onboarding_steps?: Json
          open_date?: string | null
          organization_id?: string
          phase?: string
          scoring_formula?: Json | null
          status?: string
          title?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_cycles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_cycles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_cycles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_cycles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_cycles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_cycles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_diversity_snapshots: {
        Row: {
          created_at: string | null
          cycle_id: string
          id: string
          metrics: Json
          organization_id: string
          snapshot_type: string
        }
        Insert: {
          created_at?: string | null
          cycle_id: string
          id?: string
          metrics: Json
          organization_id?: string
          snapshot_type: string
        }
        Update: {
          created_at?: string | null
          cycle_id?: string
          id?: string
          metrics?: Json
          organization_id?: string
          snapshot_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "selection_diversity_snapshots_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "selection_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_diversity_snapshots_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_evaluation_ai_suggestions: {
        Row: {
          application_id: string
          consent_snapshot_at: string
          consumed_at: string | null
          evaluation_type: string
          generated_at: string
          generation_cost_usd: number | null
          generation_inputs: Json | null
          generation_latency_ms: number | null
          id: string
          model_name: string
          model_provider: string
          organization_id: string
          prompt_version: string
          suggested_criterion_notes: Json
          suggested_overall_summary: string | null
          suggested_scores: Json
          suggested_weighted_subtotal: number | null
          superseded_by: string | null
          used_in_evaluation_id: string | null
        }
        Insert: {
          application_id: string
          consent_snapshot_at: string
          consumed_at?: string | null
          evaluation_type: string
          generated_at?: string
          generation_cost_usd?: number | null
          generation_inputs?: Json | null
          generation_latency_ms?: number | null
          id?: string
          model_name: string
          model_provider: string
          organization_id?: string
          prompt_version: string
          suggested_criterion_notes?: Json
          suggested_overall_summary?: string | null
          suggested_scores: Json
          suggested_weighted_subtotal?: number | null
          superseded_by?: string | null
          used_in_evaluation_id?: string | null
        }
        Update: {
          application_id?: string
          consent_snapshot_at?: string
          consumed_at?: string | null
          evaluation_type?: string
          generated_at?: string
          generation_cost_usd?: number | null
          generation_inputs?: Json | null
          generation_latency_ms?: number | null
          id?: string
          model_name?: string
          model_provider?: string
          organization_id?: string
          prompt_version?: string
          suggested_criterion_notes?: Json
          suggested_overall_summary?: string | null
          suggested_scores?: Json
          suggested_weighted_subtotal?: number | null
          superseded_by?: string | null
          used_in_evaluation_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_evaluation_ai_suggestions_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluation_ai_suggestions_superseded_by_fkey"
            columns: ["superseded_by"]
            isOneToOne: false
            referencedRelation: "selection_evaluation_ai_suggestions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluation_ai_suggestions_used_in_evaluation_id_fkey"
            columns: ["used_in_evaluation_id"]
            isOneToOne: false
            referencedRelation: "selection_evaluations"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_evaluation_anomalies: {
        Row: {
          alert_type: string
          application_id: string
          cycle_id: string | null
          detected_at: string
          id: string
          payload: Json
          resolved_at: string | null
          resolved_by: string | null
        }
        Insert: {
          alert_type: string
          application_id: string
          cycle_id?: string | null
          detected_at?: string
          id?: string
          payload?: Json
          resolved_at?: string | null
          resolved_by?: string | null
        }
        Update: {
          alert_type?: string
          application_id?: string
          cycle_id?: string | null
          detected_at?: string
          id?: string
          payload?: Json
          resolved_at?: string | null
          resolved_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_evaluation_anomalies_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluation_anomalies_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "selection_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluation_anomalies_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluation_anomalies_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_evaluation_anomalies_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluation_anomalies_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluation_anomalies_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_evaluations: {
        Row: {
          application_id: string
          created_at: string | null
          criterion_notes: Json | null
          evaluation_type: string
          evaluator_id: string
          id: string
          notes: string | null
          organization_id: string
          scores: Json
          submitted_at: string | null
          weighted_subtotal: number | null
        }
        Insert: {
          application_id: string
          created_at?: string | null
          criterion_notes?: Json | null
          evaluation_type: string
          evaluator_id: string
          id?: string
          notes?: string | null
          organization_id?: string
          scores?: Json
          submitted_at?: string | null
          weighted_subtotal?: number | null
        }
        Update: {
          application_id?: string
          created_at?: string | null
          criterion_notes?: Json | null
          evaluation_type?: string
          evaluator_id?: string
          id?: string
          notes?: string | null
          organization_id?: string
          scores?: Json
          submitted_at?: string | null
          weighted_subtotal?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_evaluations_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluations_evaluator_id_fkey"
            columns: ["evaluator_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluations_evaluator_id_fkey"
            columns: ["evaluator_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_evaluations_evaluator_id_fkey"
            columns: ["evaluator_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluations_evaluator_id_fkey"
            columns: ["evaluator_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluations_evaluator_id_fkey"
            columns: ["evaluator_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_evaluations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_interviews: {
        Row: {
          application_id: string
          calendar_event_id: string | null
          conducted_at: string | null
          created_at: string | null
          duration_minutes: number | null
          id: string
          interviewer_ids: string[]
          notes: string | null
          organization_id: string
          reminder_sent_at_1h: string | null
          scheduled_at: string | null
          status: string
          theme_of_interest: string | null
        }
        Insert: {
          application_id: string
          calendar_event_id?: string | null
          conducted_at?: string | null
          created_at?: string | null
          duration_minutes?: number | null
          id?: string
          interviewer_ids: string[]
          notes?: string | null
          organization_id?: string
          reminder_sent_at_1h?: string | null
          scheduled_at?: string | null
          status?: string
          theme_of_interest?: string | null
        }
        Update: {
          application_id?: string
          calendar_event_id?: string | null
          conducted_at?: string | null
          created_at?: string | null
          duration_minutes?: number | null
          id?: string
          interviewer_ids?: string[]
          notes?: string | null
          organization_id?: string
          reminder_sent_at_1h?: string | null
          scheduled_at?: string | null
          status?: string
          theme_of_interest?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_interviews_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_interviews_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_membership_snapshots: {
        Row: {
          application_id: string
          certifications: string | null
          chapter_affiliations: string[] | null
          created_at: string | null
          id: string
          is_partner_chapter: boolean | null
          membership_status: string | null
          snapshot_date: string
          source: string | null
        }
        Insert: {
          application_id: string
          certifications?: string | null
          chapter_affiliations?: string[] | null
          created_at?: string | null
          id?: string
          is_partner_chapter?: boolean | null
          membership_status?: string | null
          snapshot_date?: string
          source?: string | null
        }
        Update: {
          application_id?: string
          certifications?: string | null
          chapter_affiliations?: string[] | null
          created_at?: string | null
          id?: string
          is_partner_chapter?: boolean | null
          membership_status?: string | null
          snapshot_date?: string
          source?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_membership_snapshots_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_ranking_snapshots: {
        Row: {
          cycle_id: string
          formula_version: string | null
          id: string
          rankings: Json
          reason: string | null
          snapshot_at: string
          triggered_by: string | null
        }
        Insert: {
          cycle_id: string
          formula_version?: string | null
          id?: string
          rankings: Json
          reason?: string | null
          snapshot_at?: string
          triggered_by?: string | null
        }
        Update: {
          cycle_id?: string
          formula_version?: string | null
          id?: string
          rankings?: Json
          reason?: string | null
          snapshot_at?: string
          triggered_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "selection_ranking_snapshots_cycle_id_fkey"
            columns: ["cycle_id"]
            isOneToOne: false
            referencedRelation: "selection_cycles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_ranking_snapshots_triggered_by_fkey"
            columns: ["triggered_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_ranking_snapshots_triggered_by_fkey"
            columns: ["triggered_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "selection_ranking_snapshots_triggered_by_fkey"
            columns: ["triggered_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_ranking_snapshots_triggered_by_fkey"
            columns: ["triggered_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_ranking_snapshots_triggered_by_fkey"
            columns: ["triggered_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      selection_topic_views: {
        Row: {
          application_id: string
          id: string
          ip_address: unknown
          organization_id: string
          user_agent: string | null
          viewed_at: string
        }
        Insert: {
          application_id: string
          id?: string
          ip_address?: unknown
          organization_id?: string
          user_agent?: string | null
          viewed_at?: string
        }
        Update: {
          application_id?: string
          id?: string
          ip_address?: unknown
          organization_id?: string
          user_agent?: string | null
          viewed_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "selection_topic_views_application_id_fkey"
            columns: ["application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "selection_topic_views_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      site_config: {
        Row: {
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          key: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Update: {
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "site_config_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      sustainability_kpi_targets: {
        Row: {
          created_at: string | null
          current_value: number | null
          cycle: number
          id: string
          kpi_formula: string | null
          kpi_name: string
          notes: string | null
          organization_id: string | null
          target_unit: string | null
          target_value: number | null
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          current_value?: number | null
          cycle?: number
          id?: string
          kpi_formula?: string | null
          kpi_name: string
          notes?: string | null
          organization_id?: string | null
          target_unit?: string | null
          target_value?: number | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          current_value?: number | null
          cycle?: number
          id?: string
          kpi_formula?: string | null
          kpi_name?: string
          notes?: string | null
          organization_id?: string | null
          target_unit?: string | null
          target_value?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sustainability_kpi_targets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tags: {
        Row: {
          color: string
          created_at: string | null
          created_by: string | null
          description: string | null
          display_order: number | null
          domain: Database["public"]["Enums"]["tag_domain"]
          id: string
          is_system: boolean | null
          label_en: string | null
          label_es: string | null
          label_pt: string
          name: string
          tier: Database["public"]["Enums"]["tag_tier"]
        }
        Insert: {
          color?: string
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          display_order?: number | null
          domain?: Database["public"]["Enums"]["tag_domain"]
          id?: string
          is_system?: boolean | null
          label_en?: string | null
          label_es?: string | null
          label_pt: string
          name: string
          tier?: Database["public"]["Enums"]["tag_tier"]
        }
        Update: {
          color?: string
          created_at?: string | null
          created_by?: string | null
          description?: string | null
          display_order?: number | null
          domain?: Database["public"]["Enums"]["tag_domain"]
          id?: string
          is_system?: boolean | null
          label_en?: string | null
          label_es?: string | null
          label_pt?: string
          name?: string
          tier?: Database["public"]["Enums"]["tag_tier"]
        }
        Relationships: [
          {
            foreignKeyName: "tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tags_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      taxonomy_tags: {
        Row: {
          category: string
          id: number
          is_active: boolean
          kpi_ref: string | null
          label_en: string
          label_es: string
          label_pt: string
          tag_key: string
        }
        Insert: {
          category: string
          id?: number
          is_active?: boolean
          kpi_ref?: string | null
          label_en?: string
          label_es?: string
          label_pt: string
          tag_key: string
        }
        Update: {
          category?: string
          id?: number
          is_active?: boolean
          kpi_ref?: string | null
          label_en?: string
          label_es?: string
          label_pt?: string
          tag_key?: string
        }
        Relationships: []
      }
      tia_analyses: {
        Row: {
          analysis_data: Json | null
          analysis_id: string | null
          created_at: string | null
          id: string
          project_name: string | null
          user_id: string | null
        }
        Insert: {
          analysis_data?: Json | null
          analysis_id?: string | null
          created_at?: string | null
          id?: string
          project_name?: string | null
          user_id?: string | null
        }
        Update: {
          analysis_data?: Json | null
          analysis_id?: string | null
          created_at?: string | null
          id?: string
          project_name?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      trello_import_log: {
        Row: {
          board_name: string
          board_source: string
          cards_mapped: number
          cards_skipped: number
          cards_total: number
          id: number
          imported_at: string
          imported_by: string | null
          notes: string | null
          target_table: string
        }
        Insert: {
          board_name: string
          board_source: string
          cards_mapped?: number
          cards_skipped?: number
          cards_total?: number
          id?: number
          imported_at?: string
          imported_by?: string | null
          notes?: string | null
          target_table: string
        }
        Update: {
          board_name?: string
          board_source?: string
          cards_mapped?: number
          cards_skipped?: number
          cards_total?: number
          id?: number
          imported_at?: string
          imported_by?: string | null
          notes?: string | null
          target_table?: string
        }
        Relationships: []
      }
      tribe_continuity_overrides: {
        Row: {
          continuity_key: string
          continuity_type: string
          created_at: string
          current_cycle_code: string
          current_tribe_id: number | null
          id: number
          is_active: boolean
          leader_name: string | null
          legacy_cycle_code: string
          legacy_tribe_id: number | null
          metadata: Json
          notes: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          continuity_key: string
          continuity_type?: string
          created_at?: string
          current_cycle_code: string
          current_tribe_id?: number | null
          id?: number
          is_active?: boolean
          leader_name?: string | null
          legacy_cycle_code: string
          legacy_tribe_id?: number | null
          metadata?: Json
          notes?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          continuity_key?: string
          continuity_type?: string
          created_at?: string
          current_cycle_code?: string
          current_tribe_id?: number | null
          id?: number
          is_active?: boolean
          leader_name?: string | null
          legacy_cycle_code?: string
          legacy_tribe_id?: number | null
          metadata?: Json
          notes?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tribe_continuity_overrides_current_tribe_id_fkey"
            columns: ["current_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_legacy_tribe_id_fkey"
            columns: ["legacy_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_continuity_overrides_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_deliverables: {
        Row: {
          artifact_id: string | null
          assigned_member_id: string | null
          created_at: string
          cycle_code: string
          description: string | null
          description_i18n: Json
          due_date: string | null
          id: string
          initiative_id: string | null
          organization_id: string
          status: string
          title: string
          title_i18n: Json
          updated_at: string
        }
        Insert: {
          artifact_id?: string | null
          assigned_member_id?: string | null
          created_at?: string
          cycle_code: string
          description?: string | null
          description_i18n?: Json
          due_date?: string | null
          id?: string
          initiative_id?: string | null
          organization_id?: string
          status?: string
          title: string
          title_i18n?: Json
          updated_at?: string
        }
        Update: {
          artifact_id?: string | null
          assigned_member_id?: string | null
          created_at?: string
          cycle_code?: string
          description?: string | null
          description_i18n?: Json
          due_date?: string | null
          id?: string
          initiative_id?: string | null
          organization_id?: string
          status?: string
          title?: string
          title_i18n?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_assigned_member_id_fkey"
            columns: ["assigned_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_cycle_code_fkey"
            columns: ["cycle_code"]
            isOneToOne: false
            referencedRelation: "cycles"
            referencedColumns: ["cycle_code"]
          },
          {
            foreignKeyName: "tribe_deliverables_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_deliverables_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_kpi_contributions: {
        Row: {
          contribution_query: string | null
          created_at: string
          id: string
          initiative_id: string
          kpi_target_id: string
          notes: string | null
          organization_id: string
          updated_at: string
          weight: number
        }
        Insert: {
          contribution_query?: string | null
          created_at?: string
          id?: string
          initiative_id: string
          kpi_target_id: string
          notes?: string | null
          organization_id: string
          updated_at?: string
          weight?: number
        }
        Update: {
          contribution_query?: string | null
          created_at?: string
          id?: string
          initiative_id?: string
          kpi_target_id?: string
          notes?: string | null
          organization_id?: string
          updated_at?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "tribe_kpi_contributions_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_kpi_contributions_kpi_target_id_fkey"
            columns: ["kpi_target_id"]
            isOneToOne: false
            referencedRelation: "annual_kpi_targets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_kpi_contributions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_lineage: {
        Row: {
          created_at: string
          created_by: string | null
          current_tribe_id: number
          cycle_scope: string | null
          id: number
          is_active: boolean
          legacy_tribe_id: number
          metadata: Json
          notes: string | null
          relation_type: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          current_tribe_id: number
          cycle_scope?: string | null
          id?: number
          is_active?: boolean
          legacy_tribe_id: number
          metadata?: Json
          notes?: string | null
          relation_type: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          current_tribe_id?: number
          cycle_scope?: string | null
          id?: number
          is_active?: boolean
          legacy_tribe_id?: number
          metadata?: Json
          notes?: string | null
          relation_type?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_current_tribe_id_fkey"
            columns: ["current_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_legacy_tribe_id_fkey"
            columns: ["legacy_tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_lineage_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_meeting_slots: {
        Row: {
          created_at: string | null
          day_of_week: number
          id: string
          is_active: boolean | null
          time_end: string
          time_start: string
          tribe_id: number
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          day_of_week: number
          id?: string
          is_active?: boolean | null
          time_end: string
          time_start: string
          tribe_id: number
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          day_of_week?: number
          id?: string
          is_active?: boolean | null
          time_end?: string
          time_start?: string
          tribe_id?: number
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tribe_meeting_slots_tribe_id_fkey"
            columns: ["tribe_id"]
            isOneToOne: false
            referencedRelation: "tribes"
            referencedColumns: ["id"]
          },
        ]
      }
      tribe_selections: {
        Row: {
          id: string
          member_id: string | null
          selected_at: string | null
          tribe_id: number
        }
        Insert: {
          id?: string
          member_id?: string | null
          selected_at?: string | null
          tribe_id: number
        }
        Update: {
          id?: string
          member_id?: string | null
          selected_at?: string | null
          tribe_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribe_selections_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      tribes: {
        Row: {
          drive_url: string | null
          id: number
          is_active: boolean
          leader_member_id: string | null
          legacy_board_url: string | null
          meeting_link: string | null
          meeting_schedule: string | null
          meeting_time_end: string | null
          meeting_time_start: string | null
          miro_url: string | null
          name: string
          name_i18n: Json | null
          notes: string | null
          organization_id: string
          quadrant: number
          quadrant_name: string
          quadrant_name_i18n: Json | null
          updated_at: string | null
          updated_by: string | null
          video_duration: string | null
          video_url: string | null
          whatsapp_url: string | null
          workstream_type: string
        }
        Insert: {
          drive_url?: string | null
          id: number
          is_active?: boolean
          leader_member_id?: string | null
          legacy_board_url?: string | null
          meeting_link?: string | null
          meeting_schedule?: string | null
          meeting_time_end?: string | null
          meeting_time_start?: string | null
          miro_url?: string | null
          name: string
          name_i18n?: Json | null
          notes?: string | null
          organization_id?: string
          quadrant: number
          quadrant_name: string
          quadrant_name_i18n?: Json | null
          updated_at?: string | null
          updated_by?: string | null
          video_duration?: string | null
          video_url?: string | null
          whatsapp_url?: string | null
          workstream_type?: string
        }
        Update: {
          drive_url?: string | null
          id?: number
          is_active?: boolean
          leader_member_id?: string | null
          legacy_board_url?: string | null
          meeting_link?: string | null
          meeting_schedule?: string | null
          meeting_time_end?: string | null
          meeting_time_start?: string | null
          miro_url?: string | null
          name?: string
          name_i18n?: Json | null
          notes?: string | null
          organization_id?: string
          quadrant?: number
          quadrant_name?: string
          quadrant_name_i18n?: Json | null
          updated_at?: string | null
          updated_by?: string | null
          video_duration?: string | null
          video_url?: string | null
          whatsapp_url?: string | null
          workstream_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_leader_member_id_fkey"
            columns: ["leader_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_quadrant_fkey"
            columns: ["quadrant"]
            isOneToOne: false
            referencedRelation: "quadrants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tribes_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      user_profiles: {
        Row: {
          avatar_url: string | null
          company: string | null
          created_at: string | null
          email: string | null
          full_name: string | null
          id: string
          role: string
          updated_at: string | null
        }
        Insert: {
          avatar_url?: string | null
          company?: string | null
          created_at?: string | null
          email?: string | null
          full_name?: string | null
          id: string
          role?: string
          updated_at?: string | null
        }
        Update: {
          avatar_url?: string | null
          company?: string | null
          created_at?: string | null
          email?: string | null
          full_name?: string | null
          id?: string
          role?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      vep_opportunities: {
        Row: {
          chapter_posted: string | null
          created_at: string | null
          eligibility: string | null
          end_date: string | null
          essay_mapping: Json
          id: string
          is_active: boolean | null
          opportunity_id: string
          positions_available: number | null
          requirements: string | null
          role_default: string | null
          start_date: string | null
          time_commitment: string | null
          title: string
          vep_url: string | null
        }
        Insert: {
          chapter_posted?: string | null
          created_at?: string | null
          eligibility?: string | null
          end_date?: string | null
          essay_mapping?: Json
          id?: string
          is_active?: boolean | null
          opportunity_id: string
          positions_available?: number | null
          requirements?: string | null
          role_default?: string | null
          start_date?: string | null
          time_commitment?: string | null
          title: string
          vep_url?: string | null
        }
        Update: {
          chapter_posted?: string | null
          created_at?: string | null
          eligibility?: string | null
          end_date?: string | null
          essay_mapping?: Json
          id?: string
          is_active?: boolean | null
          opportunity_id?: string
          positions_available?: number | null
          requirements?: string | null
          role_default?: string | null
          start_date?: string | null
          time_commitment?: string | null
          title?: string
          vep_url?: string | null
        }
        Relationships: []
      }
      vep_reconciliation_baselines: {
        Row: {
          captured_at: string
          captured_by: string | null
          id: string
          label: string
          notes: string | null
          organization_id: string
          summary: Json
        }
        Insert: {
          captured_at?: string
          captured_by?: string | null
          id?: string
          label: string
          notes?: string | null
          organization_id?: string
          summary: Json
        }
        Update: {
          captured_at?: string
          captured_by?: string | null
          id?: string
          label?: string
          notes?: string | null
          organization_id?: string
          summary?: Json
        }
        Relationships: [
          {
            foreignKeyName: "vep_reconciliation_baselines_captured_by_fkey"
            columns: ["captured_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vep_reconciliation_baselines_captured_by_fkey"
            columns: ["captured_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "vep_reconciliation_baselines_captured_by_fkey"
            columns: ["captured_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vep_reconciliation_baselines_captured_by_fkey"
            columns: ["captured_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vep_reconciliation_baselines_captured_by_fkey"
            columns: ["captured_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vep_reconciliation_baselines_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      visitor_leads: {
        Row: {
          auto_promote_eligible: boolean | null
          chapter_interest: string | null
          contacted_at: string | null
          contacted_by: string | null
          created_at: string | null
          dedupe_email_normalized: string | null
          dismissal_reason: string | null
          dismissed_at: string | null
          dismissed_by: string | null
          email: string
          id: string
          lgpd_consent: boolean
          message: string | null
          name: string
          organization_id: string
          phone: string | null
          promoted_at: string | null
          promoted_by: string | null
          promoted_to_application_id: string | null
          referrer_member_id: string | null
          role_interest: string | null
          source: string | null
          status: string | null
          utm_data: Json | null
        }
        Insert: {
          auto_promote_eligible?: boolean | null
          chapter_interest?: string | null
          contacted_at?: string | null
          contacted_by?: string | null
          created_at?: string | null
          dedupe_email_normalized?: string | null
          dismissal_reason?: string | null
          dismissed_at?: string | null
          dismissed_by?: string | null
          email: string
          id?: string
          lgpd_consent?: boolean
          message?: string | null
          name: string
          organization_id?: string
          phone?: string | null
          promoted_at?: string | null
          promoted_by?: string | null
          promoted_to_application_id?: string | null
          referrer_member_id?: string | null
          role_interest?: string | null
          source?: string | null
          status?: string | null
          utm_data?: Json | null
        }
        Update: {
          auto_promote_eligible?: boolean | null
          chapter_interest?: string | null
          contacted_at?: string | null
          contacted_by?: string | null
          created_at?: string | null
          dedupe_email_normalized?: string | null
          dismissal_reason?: string | null
          dismissed_at?: string | null
          dismissed_by?: string | null
          email?: string
          id?: string
          lgpd_consent?: boolean
          message?: string | null
          name?: string
          organization_id?: string
          phone?: string | null
          promoted_at?: string | null
          promoted_by?: string | null
          promoted_to_application_id?: string | null
          referrer_member_id?: string | null
          role_interest?: string | null
          source?: string | null
          status?: string | null
          utm_data?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "visitor_leads_contacted_by_fkey"
            columns: ["contacted_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_contacted_by_fkey"
            columns: ["contacted_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "visitor_leads_contacted_by_fkey"
            columns: ["contacted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_contacted_by_fkey"
            columns: ["contacted_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_contacted_by_fkey"
            columns: ["contacted_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_dismissed_by_fkey"
            columns: ["dismissed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_dismissed_by_fkey"
            columns: ["dismissed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "visitor_leads_dismissed_by_fkey"
            columns: ["dismissed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_dismissed_by_fkey"
            columns: ["dismissed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_dismissed_by_fkey"
            columns: ["dismissed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "visitor_leads_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_promoted_by_fkey"
            columns: ["promoted_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_promoted_to_application_id_fkey"
            columns: ["promoted_to_application_id"]
            isOneToOne: false
            referencedRelation: "selection_applications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "visitor_leads_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "visitor_leads_referrer_member_id_fkey"
            columns: ["referrer_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
        ]
      }
      volunteer_applications: {
        Row: {
          app_status: string | null
          application_id: string
          areas_of_interest: string | null
          certifications: string[] | null
          city: string | null
          country: string | null
          created_at: string
          cycle: number
          email: string
          essay_answers: Json | null
          first_name: string
          id: string
          industry: string | null
          is_existing_member: boolean
          label: string | null
          last_name: string
          member_id: string | null
          membership_status: string | null
          opportunity_id: string | null
          organization_id: string
          pmi_id: string | null
          reason_for_applying: string | null
          resume_url: string | null
          snapshot_date: string
          specialty: string | null
          state: string | null
        }
        Insert: {
          app_status?: string | null
          application_id: string
          areas_of_interest?: string | null
          certifications?: string[] | null
          city?: string | null
          country?: string | null
          created_at?: string
          cycle: number
          email: string
          essay_answers?: Json | null
          first_name: string
          id?: string
          industry?: string | null
          is_existing_member?: boolean
          label?: string | null
          last_name: string
          member_id?: string | null
          membership_status?: string | null
          opportunity_id?: string | null
          organization_id?: string
          pmi_id?: string | null
          reason_for_applying?: string | null
          resume_url?: string | null
          snapshot_date: string
          specialty?: string | null
          state?: string | null
        }
        Update: {
          app_status?: string | null
          application_id?: string
          areas_of_interest?: string | null
          certifications?: string[] | null
          city?: string | null
          country?: string | null
          created_at?: string
          cycle?: number
          email?: string
          essay_answers?: Json | null
          first_name?: string
          id?: string
          industry?: string | null
          is_existing_member?: boolean
          label?: string | null
          last_name?: string
          member_id?: string | null
          membership_status?: string | null
          opportunity_id?: string | null
          organization_id?: string
          pmi_id?: string | null
          reason_for_applying?: string | null
          resume_url?: string | null
          snapshot_date?: string
          specialty?: string | null
          state?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_applications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_applications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      webinar_lifecycle_events: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          id: number
          metadata: Json | null
          new_status: string | null
          old_status: string | null
          webinar_id: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          id?: number
          metadata?: Json | null
          new_status?: string | null
          old_status?: string | null
          webinar_id: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          id?: number
          metadata?: Json | null
          new_status?: string | null
          old_status?: string | null
          webinar_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "webinar_lifecycle_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_lifecycle_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "webinar_lifecycle_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_lifecycle_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_lifecycle_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_lifecycle_events_webinar_id_fkey"
            columns: ["webinar_id"]
            isOneToOne: false
            referencedRelation: "webinars"
            referencedColumns: ["id"]
          },
        ]
      }
      webinar_proposals: {
        Row: {
          created_at: string
          format_type: string
          id: string
          notes: string | null
          organization_id: string
          proposed_by_tribe_id: number | null
          proposed_speakers: string[] | null
          proposed_title: string
          proposer_member_id: string
          quadrant_anchor: number | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          series_id: string | null
          status: string
          themes: string[] | null
          updated_at: string
          webinar_id: string | null
        }
        Insert: {
          created_at?: string
          format_type: string
          id?: string
          notes?: string | null
          organization_id?: string
          proposed_by_tribe_id?: number | null
          proposed_speakers?: string[] | null
          proposed_title: string
          proposer_member_id: string
          quadrant_anchor?: number | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          series_id?: string | null
          status?: string
          themes?: string[] | null
          updated_at?: string
          webinar_id?: string | null
        }
        Update: {
          created_at?: string
          format_type?: string
          id?: string
          notes?: string | null
          organization_id?: string
          proposed_by_tribe_id?: number | null
          proposed_speakers?: string[] | null
          proposed_title?: string
          proposer_member_id?: string
          quadrant_anchor?: number | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          series_id?: string | null
          status?: string
          themes?: string[] | null
          updated_at?: string
          webinar_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "webinar_proposals_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "webinar_proposals_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_proposer_member_id_fkey"
            columns: ["proposer_member_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_quadrant_anchor_fkey"
            columns: ["quadrant_anchor"]
            isOneToOne: false
            referencedRelation: "quadrants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "webinar_proposals_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "publication_series"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinar_proposals_webinar_id_fkey"
            columns: ["webinar_id"]
            isOneToOne: false
            referencedRelation: "webinars"
            referencedColumns: ["id"]
          },
        ]
      }
      webinars: {
        Row: {
          board_item_id: string | null
          briefing_doc_url: string | null
          chapter_code: string
          co_manager_ids: string[] | null
          comms_kickoff_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          duration_min: number
          event_id: string | null
          format_type: string | null
          id: string
          initiative_id: string | null
          meeting_link: string | null
          notes: string | null
          organization_id: string
          organizer_id: string | null
          promo_kit_url: string | null
          scheduled_at: string
          series_id: string | null
          series_position: number | null
          status: string
          sympla_event_url: string | null
          title: string
          tribe_anchors: number[] | null
          updated_at: string
          youtube_url: string | null
        }
        Insert: {
          board_item_id?: string | null
          briefing_doc_url?: string | null
          chapter_code: string
          co_manager_ids?: string[] | null
          comms_kickoff_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          duration_min?: number
          event_id?: string | null
          format_type?: string | null
          id?: string
          initiative_id?: string | null
          meeting_link?: string | null
          notes?: string | null
          organization_id?: string
          organizer_id?: string | null
          promo_kit_url?: string | null
          scheduled_at: string
          series_id?: string | null
          series_position?: number | null
          status?: string
          sympla_event_url?: string | null
          title: string
          tribe_anchors?: number[] | null
          updated_at?: string
          youtube_url?: string | null
        }
        Update: {
          board_item_id?: string | null
          briefing_doc_url?: string | null
          chapter_code?: string
          co_manager_ids?: string[] | null
          comms_kickoff_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          duration_min?: number
          event_id?: string | null
          format_type?: string | null
          id?: string
          initiative_id?: string | null
          meeting_link?: string | null
          notes?: string | null
          organization_id?: string
          organizer_id?: string | null
          promo_kit_url?: string | null
          scheduled_at?: string
          series_id?: string | null
          series_position?: number | null
          status?: string
          sympla_event_url?: string | null
          title?: string
          tribe_anchors?: number[] | null
          updated_at?: string
          youtube_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "webinars_board_item_id_fkey"
            columns: ["board_item_id"]
            isOneToOne: false
            referencedRelation: "board_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "active_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "member_attendance_summary"
            referencedColumns: ["member_id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "members_public_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_organizer_id_fkey"
            columns: ["organizer_id"]
            isOneToOne: false
            referencedRelation: "public_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "webinars_series_id_fkey"
            columns: ["series_id"]
            isOneToOne: false
            referencedRelation: "publication_series"
            referencedColumns: ["id"]
          },
        ]
      }
      wiki_pages: {
        Row: {
          authors: string[] | null
          content: string
          created_at: string | null
          domain: string
          fts: unknown
          id: string
          ip_track: string | null
          license: string | null
          path: string
          source_repo: string
          source_sha: string | null
          summary: string | null
          synced_at: string | null
          tags: string[] | null
          title: string
          updated_at: string | null
        }
        Insert: {
          authors?: string[] | null
          content?: string
          created_at?: string | null
          domain: string
          fts?: unknown
          id?: string
          ip_track?: string | null
          license?: string | null
          path: string
          source_repo?: string
          source_sha?: string | null
          summary?: string | null
          synced_at?: string | null
          tags?: string[] | null
          title: string
          updated_at?: string | null
        }
        Update: {
          authors?: string[] | null
          content?: string
          created_at?: string | null
          domain?: string
          fts?: unknown
          id?: string
          ip_track?: string | null
          license?: string | null
          path?: string
          source_repo?: string
          source_sha?: string | null
          summary?: string | null
          synced_at?: string | null
          tags?: string[] | null
          title?: string
          updated_at?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      active_members: {
        Row: {
          chapter: string | null
          country: string | null
          cpmai_certified: boolean | null
          cpmai_certified_at: string | null
          created_at: string | null
          credly_badges: Json | null
          credly_url: string | null
          credly_verified_at: string | null
          current_cycle_active: boolean | null
          cycles: string[] | null
          designations: string[] | null
          id: string | null
          initiative_id: string | null
          is_active: boolean | null
          last_active_pages: string[] | null
          last_seen_at: string | null
          linkedin_url: string | null
          member_status: string | null
          name: string | null
          onboarding_dismissed_at: string | null
          operational_role: string | null
          organization_id: string | null
          person_id: string | null
          photo_url: string | null
          profile_completed_at: string | null
          share_address: boolean | null
          share_birth_date: boolean | null
          share_whatsapp: boolean | null
          state: string | null
          status_changed_at: string | null
          total_sessions: number | null
          tribe_id: number | null
          updated_at: string | null
        }
        Insert: {
          chapter?: string | null
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          designations?: string[] | null
          id?: string | null
          initiative_id?: string | null
          is_active?: boolean | null
          last_active_pages?: string[] | null
          last_seen_at?: string | null
          linkedin_url?: string | null
          member_status?: string | null
          name?: string | null
          onboarding_dismissed_at?: string | null
          operational_role?: string | null
          organization_id?: string | null
          person_id?: string | null
          photo_url?: string | null
          profile_completed_at?: string | null
          share_address?: boolean | null
          share_birth_date?: boolean | null
          share_whatsapp?: boolean | null
          state?: string | null
          status_changed_at?: string | null
          total_sessions?: number | null
          tribe_id?: number | null
          updated_at?: string | null
        }
        Update: {
          chapter?: string | null
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          designations?: string[] | null
          id?: string | null
          initiative_id?: string | null
          is_active?: boolean | null
          last_active_pages?: string[] | null
          last_seen_at?: string | null
          linkedin_url?: string | null
          member_status?: string | null
          name?: string | null
          onboarding_dismissed_at?: string | null
          operational_role?: string | null
          organization_id?: string | null
          person_id?: string | null
          photo_url?: string | null
          profile_completed_at?: string | null
          share_address?: boolean | null
          share_birth_date?: boolean | null
          share_whatsapp?: boolean | null
          state?: string | null
          status_changed_at?: string | null
          total_sessions?: number | null
          tribe_id?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "members_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "members_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      auth_engagements: {
        Row: {
          agreement_certificate_id: string | null
          auth_id: string | null
          end_date: string | null
          engagement_id: string | null
          initiative_id: string | null
          is_authoritative: boolean | null
          kind: string | null
          legacy_member_id: string | null
          legacy_tribe_id: number | null
          legal_basis: string | null
          organization_id: string | null
          person_id: string | null
          requires_agreement: boolean | null
          role: string | null
          start_date: string | null
          status: string | null
        }
        Relationships: [
          {
            foreignKeyName: "engagements_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_kind_fkey"
            columns: ["kind"]
            isOneToOne: false
            referencedRelation: "engagement_kinds"
            referencedColumns: ["slug"]
          },
          {
            foreignKeyName: "engagements_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "engagements_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "persons"
            referencedColumns: ["id"]
          },
        ]
      }
      cycle_tribe_dim: {
        Row: {
          cycle_code: string | null
          dim_id: number | null
          is_active: boolean | null
          leader_id: string | null
          leader_name: string | null
          leader_photo: string | null
          member_count: number | null
          parent_legacy_tribe_id: number | null
          parent_relation_type: string | null
          quadrant: number | null
          quadrant_name: string | null
          tribe_name: string | null
          tribe_number: number | null
          tribe_type: string | null
        }
        Relationships: []
      }
      impact_hours_summary: {
        Row: {
          impact_hours: number | null
          impact_hours_raw: number | null
          total_attendances: number | null
          total_events: number | null
          tribe_id: number | null
        }
        Relationships: []
      }
      impact_hours_total: {
        Row: {
          annual_target_hours: number | null
          percent_of_target: number | null
          total_attendances: number | null
          total_events: number | null
          total_impact_hours: number | null
        }
        Relationships: []
      }
      member_attendance_summary: {
        Row: {
          chapter: string | null
          designations: string[] | null
          events_attended: number | null
          member_id: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
          role: string | null
          total_hours: number | null
        }
        Relationships: []
      }
      members_public_safe: {
        Row: {
          chapter: string | null
          cpmai_certified: boolean | null
          created_at: string | null
          credly_badges: Json | null
          current_cycle_active: boolean | null
          designations: string[] | null
          id: string | null
          is_active: boolean | null
          linkedin_url: string | null
          member_status: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
          tribe_id: number | null
        }
        Insert: {
          chapter?: string | null
          cpmai_certified?: boolean | null
          created_at?: string | null
          credly_badges?: Json | null
          current_cycle_active?: boolean | null
          designations?: string[] | null
          id?: string | null
          is_active?: boolean | null
          linkedin_url?: string | null
          member_status?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          tribe_id?: number | null
        }
        Update: {
          chapter?: string | null
          cpmai_certified?: boolean | null
          created_at?: string | null
          credly_badges?: Json | null
          current_cycle_active?: boolean | null
          designations?: string[] | null
          id?: string | null
          is_active?: boolean | null
          linkedin_url?: string | null
          member_status?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          tribe_id?: number | null
        }
        Relationships: []
      }
      public_members: {
        Row: {
          chapter: string | null
          country: string | null
          cpmai_certified: boolean | null
          cpmai_certified_at: string | null
          created_at: string | null
          credly_badges: Json | null
          credly_url: string | null
          credly_verified_at: string | null
          current_cycle_active: boolean | null
          cycles: string[] | null
          designations: string[] | null
          id: string | null
          initiative_id: string | null
          is_active: boolean | null
          linkedin_url: string | null
          member_status: string | null
          name: string | null
          operational_role: string | null
          photo_url: string | null
          share_whatsapp: boolean | null
          signature_url: string | null
          state: string | null
          tribe_id: number | null
        }
        Insert: {
          chapter?: string | null
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          designations?: string[] | null
          id?: string | null
          initiative_id?: string | null
          is_active?: boolean | null
          linkedin_url?: string | null
          member_status?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          share_whatsapp?: boolean | null
          signature_url?: string | null
          state?: string | null
          tribe_id?: number | null
        }
        Update: {
          chapter?: string | null
          country?: string | null
          cpmai_certified?: boolean | null
          cpmai_certified_at?: string | null
          created_at?: string | null
          credly_badges?: Json | null
          credly_url?: string | null
          credly_verified_at?: string | null
          current_cycle_active?: boolean | null
          cycles?: string[] | null
          designations?: string[] | null
          id?: string | null
          initiative_id?: string | null
          is_active?: boolean | null
          linkedin_url?: string | null
          member_status?: string | null
          name?: string | null
          operational_role?: string | null
          photo_url?: string | null
          share_whatsapp?: boolean | null
          signature_url?: string | null
          state?: string | null
          tribe_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "members_initiative_id_fkey"
            columns: ["initiative_id"]
            isOneToOne: false
            referencedRelation: "initiatives"
            referencedColumns: ["id"]
          },
        ]
      }
      recurring_event_groups: {
        Row: {
          first_date: string | null
          last_date: string | null
          meeting_link: string | null
          past_events: number | null
          recurrence_group: string | null
          total_events: number | null
          tribe_id: number | null
          type: string | null
          upcoming_events: number | null
        }
        Relationships: []
      }
      v_ai_human_concordance: {
        Row: {
          criterion_key: string | null
          evaluation_type: string | null
          mae: number | null
          mean_ai_score: number | null
          mean_human_score: number | null
          model_name: string | null
          mse: number | null
          n_pairs: number | null
          prompt_version: string | null
          stddev_diff: number | null
        }
        Relationships: []
      }
      v_cron_last_success: {
        Row: {
          completed_at: string | null
          metrics: Json | null
          organization_id: string | null
          scheduled_for: string | null
          worker_name: string | null
        }
        Relationships: []
      }
      vw_exec_cert_timeline: {
        Row: {
          avg_days_to_tier1: number | null
          avg_days_to_tier2: number | null
          cohort_month: string | null
          members_in_cohort: number | null
          members_with_tier1: number | null
          members_with_tier2: number | null
          pct_with_tier1: number | null
          pct_with_tier2: number | null
        }
        Relationships: []
      }
      vw_exec_skills_radar: {
        Row: {
          avg_points: number | null
          badges_count: number | null
          members_with_signal: number | null
          radar_axis: string | null
          total_points: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      _artia_safe_event_summary: {
        Args: { p_end_date: string; p_start_date: string }
        Returns: Json
      }
      _artia_safe_monthly_metrics: {
        Args: { p_month: number; p_year: number }
        Returns: Json
      }
      _audit_classify_function_gate: {
        Args: { p_function_name: string }
        Returns: Json
      }
      _audit_function_acl: { Args: { p_function_name: string }; Returns: Json }
      _audit_list_public_function_bodies: {
        Args: never
        Returns: {
          body_md5: string
          identity_args: string
          is_secdef: boolean
          proname: string
          prosrc_len: number
        }[]
      }
      _audit_list_public_functions: {
        Args: never
        Returns: {
          identity_args: string
          is_secdef: boolean
          proname: string
        }[]
      }
      _audit_list_public_tables: {
        Args: never
        Returns: {
          table_name: string
        }[]
      }
      _audit_list_revoked_secdef_fns_with_rls_refs: {
        Args: never
        Returns: {
          args: string
          policy_clause: string
          policy_name: string
          qualified_name: string
          table_name: string
        }[]
      }
      _audit_preview_gate_eligibles_drift: { Args: never; Returns: Json }
      _cacheable_preview_doc_types: { Args: never; Returns: string[] }
      _can_manage_event: { Args: { p_event_id: string }; Returns: boolean }
      _can_sign_gate: {
        Args: {
          p_chain_id: string
          p_doc_type?: string
          p_gate_kind: string
          p_member_id: string
          p_submitter_id?: string
        }
        Returns: boolean
      }
      _compute_pert_cutoff_core: {
        Args: {
          p_actor_id?: string
          p_cycle_id: string
          p_filter_active_only?: boolean
          p_role?: string
          p_score_column?: string
        }
        Returns: Json
      }
      _delivery_mode_for: { Args: { p_type: string }; Returns: string }
      _enqueue_engagement_welcome: {
        Args: { p_engagement_id: string }
        Returns: undefined
      }
      _enqueue_gate_notifications: {
        Args: { p_chain_id: string; p_event: string; p_gate_kind?: string }
        Returns: number
      }
      _extract_date_from_filename: {
        Args: { p_filename: string }
        Returns: string
      }
      _get_peer_review_eligibility: {
        Args: { p_application_id: string }
        Returns: {
          last_invited_at: string
          load_count: number
          peer_email: string
          peer_member_id: string
          peer_name: string
        }[]
      }
      _get_vault_secret: { Args: { p_name: string }; Returns: string }
      _grant_auto_xp: {
        Args: {
          p_reason: string
          p_recipient_id: string
          p_ref_id: string
          p_slug: string
        }
        Returns: undefined
      }
      _ip_ratify_cta_link: {
        Args: { p_chain_id: string; p_gate_kind: string }
        Returns: string
      }
      _log_application_pii_access: {
        Args: {
          p_accessor_id: string
          p_application_id: string
          p_context: string
          p_fields: string[]
        }
        Returns: undefined
      }
      _log_gate_attempt: {
        Args: {
          p_application_id: string
          p_bypass_granted: boolean
          p_bypass_requested: boolean
          p_caller_id: string
          p_gate_failed_code: string
          p_gate_failed_reason: string
          p_gate_passed: boolean
          p_organization_id: string
          p_payload: Json
          p_rpc_name: string
        }
        Returns: undefined
      }
      _pmi_vep_sync_cycle_app_id_stats: {
        Args: never
        Returns: {
          cycle_code: string
          cycle_id: string
          max_app_id: number
          min_app_id: number
          sample_count: number
        }[]
      }
      _recompute_application_pert: {
        Args: { p_application_id: string }
        Returns: undefined
      }
      _refresh_preview_gate_eligibles_for_member: {
        Args: { p_member_id: string }
        Returns: undefined
      }
      _should_offer_enrichment: {
        Args: { p_ai_analysis: Json }
        Returns: boolean
      }
      _sync_interview_to_event: {
        Args: { p_interview_id: string }
        Returns: string
      }
      _test_detect_inactive_with_threshold: {
        Args: { p_threshold: number }
        Returns: Json
      }
      _test_invariants_with_synthetic_breach: {
        Args: { p_breach: string }
        Returns: Json
      }
      _v4_active_initiatives_with_leaders: {
        Args: never
        Returns: {
          initiative_id: string
          kind: string
          legacy_tribe_id: number
          name: string
        }[]
      }
      _v4_initiative_leader_member_ids: {
        Args: { p_tribe_id: number }
        Returns: string[]
      }
      _v4_leader_member_ids_by_initiative: {
        Args: { p_initiative_id: string }
        Returns: string[]
      }
      _v4_tribe_leader_member_id: {
        Args: { p_tribe_id: number }
        Returns: string
      }
      _validate_gates_shape: { Args: { p_gates: Json }; Returns: boolean }
      accept_privacy_consent: { Args: { p_version?: string }; Returns: Json }
      activate_initiative: { Args: { p_initiative_id: string }; Returns: Json }
      add_checklist_item: {
        Args: {
          p_assigned_to?: string
          p_board_item_id: string
          p_position?: number
          p_target_date?: string
          p_text: string
        }
        Returns: string
      }
      add_partner_attachment: {
        Args: {
          p_description?: string
          p_entity_id?: string
          p_file_name?: string
          p_file_size?: number
          p_file_type?: string
          p_file_url?: string
          p_interaction_id?: string
        }
        Returns: Json
      }
      add_partner_interaction: {
        Args: {
          p_details: string
          p_follow_up_date: string
          p_interaction_type: string
          p_next_action: string
          p_outcome: string
          p_partner_id: string
          p_summary: string
        }
        Returns: Json
      }
      add_publication_submission_author: {
        Args: {
          p_author_order?: number
          p_is_corresponding?: boolean
          p_member_id: string
          p_submission_id: string
        }
        Returns: string
      }
      admin_anonymize_member: { Args: { p_member_id: string }; Returns: Json }
      admin_archive_board_item: {
        Args: { p_item_id: string; p_reason?: string }
        Returns: Json
      }
      admin_archive_project_board: {
        Args: {
          p_archive_items?: boolean
          p_board_id: string
          p_reason?: string
        }
        Returns: Json
      }
      admin_bulk_allocate_tribe: {
        Args: { p_member_ids: string[]; p_tribe_id: number }
        Returns: Json
      }
      admin_bulk_mark_attendance: {
        Args: { p_event_id: string; p_member_ids: string[]; p_present: boolean }
        Returns: Json
      }
      admin_bulk_set_status: {
        Args: { p_is_active: boolean; p_member_ids: string[] }
        Returns: Json
      }
      admin_change_tribe_leader: {
        Args: { p_new_leader_id: string; p_reason: string; p_tribe_id: number }
        Returns: Json
      }
      admin_check_ingestion_source_timeout: {
        Args: { p_source: string; p_started_at: string }
        Returns: Json
      }
      admin_deactivate_member: {
        Args: { p_member_id: string; p_reason: string }
        Returns: Json
      }
      admin_deactivate_tribe: {
        Args: { p_reason: string; p_tribe_id: number }
        Returns: Json
      }
      admin_decide_dual_track: {
        Args: {
          p_application_id: string
          p_feedback?: string
          p_leader_decision: string
          p_researcher_decision: string
        }
        Returns: Json
      }
      admin_detect_board_taxonomy_drift: { Args: never; Returns: Json }
      admin_detect_data_anomalies: {
        Args: { p_auto_fix: boolean }
        Returns: Json
      }
      admin_ensure_communication_tribe: {
        Args: {
          p_name: string
          p_notes: string
          p_quadrant: number
          p_quadrant_name: string
        }
        Returns: Json
      }
      admin_finalize_ingestion_batch: {
        Args: { p_batch_id: string; p_status: string; p_summary: Json }
        Returns: Json
      }
      admin_force_tribe_selection: {
        Args: { p_member_id: string; p_tribe_id: number }
        Returns: Json
      }
      admin_generate_volunteer_term: {
        Args: { p_member_id: string }
        Returns: Json
      }
      admin_get_anomaly_report: { Args: never; Returns: Json }
      admin_get_campaign_stats: { Args: { p_send_id: string }; Returns: Json }
      admin_get_ingestion_source_policy: {
        Args: { p_source: string }
        Returns: Json
      }
      admin_get_member_details: { Args: { p_member_id: string }; Returns: Json }
      admin_get_tribe_allocations: { Args: never; Returns: Json }
      admin_inactivate_member: {
        Args: { p_member_id: string; p_reason?: string }
        Returns: Json
      }
      admin_link_board_to_legacy_tribe: {
        Args: {
          p_board_id: string
          p_confidence_score: number
          p_legacy_tribe_id: number
          p_metadata: Json
          p_notes: string
          p_relation_type: string
        }
        Returns: Json
      }
      admin_link_communication_boards: {
        Args: { p_tribe_id?: number }
        Returns: Json
      }
      admin_link_member_to_legacy_tribe: {
        Args: {
          p_chapter_snapshot: string
          p_confidence_score: number
          p_cycle_code: string
          p_legacy_tribe_id: number
          p_link_type: string
          p_member_id: string
          p_metadata: Json
          p_role_snapshot: string
        }
        Returns: Json
      }
      admin_list_archived_board_items: {
        Args: { p_board_id?: string; p_limit?: number }
        Returns: {
          assignee_name: string
          board_id: string
          board_name: string
          board_scope: string
          domain_key: string
          due_date: string
          id: string
          title: string
          updated_at: string
        }[]
      }
      admin_list_members: {
        Args: {
          p_search?: string
          p_status?: string
          p_tier?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      admin_list_members_with_pii: {
        Args: { p_tribe_id?: number }
        Returns: Json
      }
      admin_list_tribe_lineage: {
        Args: { p_include_inactive?: boolean }
        Returns: {
          current_tribe_id: number
          current_tribe_name: string
          cycle_scope: string
          id: number
          is_active: boolean
          legacy_tribe_id: number
          legacy_tribe_name: string
          metadata: Json
          notes: string
          relation_type: string
          updated_at: string
        }[]
      }
      admin_list_tribes: {
        Args: { p_include_inactive?: boolean }
        Returns: {
          active_members: number
          id: number
          is_active: boolean
          leader_member_id: string
          leader_name: string
          name: string
          quadrant: number
          quadrant_name: string
          total_members: number
        }[]
      }
      admin_manage_board_member: {
        Args: {
          p_action?: string
          p_board_id: string
          p_board_role?: string
          p_member_id: string
        }
        Returns: Json
      }
      admin_manage_comms_channel: {
        Args: {
          p_action: string
          p_api_key: string
          p_channel: string
          p_config: Json
          p_oauth_refresh_token: string
          p_oauth_token: string
          p_token_expires_at: string
        }
        Returns: Json
      }
      admin_manage_cycle: {
        Args: {
          p_abbr: string
          p_action: string
          p_color: string
          p_cycle_code: string
          p_end: string
          p_label: string
          p_sort: number
          p_start: string
        }
        Returns: Json
      }
      admin_manage_partner_entity: {
        Args: {
          p_action: string
          p_chapter?: string
          p_contact_email?: string
          p_contact_name?: string
          p_cycle_code?: string
          p_description?: string
          p_entity_type?: string
          p_id?: string
          p_name?: string
          p_notes?: string
          p_partnership_date?: string
          p_status?: string
        }
        Returns: Json
      }
      admin_manage_publication: {
        Args: { p_action: string; p_data: Json }
        Returns: Json
      }
      admin_map_notion_item_to_board: {
        Args: {
          p_apply_insert: boolean
          p_board_id: string
          p_position: number
          p_staging_id: number
          p_status: string
        }
        Returns: Json
      }
      admin_move_application_to_cycle: {
        Args: {
          p_application_id: string
          p_reason?: string
          p_target_cycle_id: string
        }
        Returns: Json
      }
      admin_move_member_tribe: {
        Args: { p_member_id: string; p_new_tribe_id: number; p_reason: string }
        Returns: Json
      }
      admin_offboard_member: {
        Args: {
          p_member_id: string
          p_new_status: string
          p_reason_category: string
          p_reason_detail?: string
          p_reassign_to?: string
        }
        Returns: Json
      }
      admin_preview_campaign: {
        Args: { p_preview_member_id?: string; p_template_id: string }
        Returns: Json
      }
      admin_reactivate_member: {
        Args: { p_member_id: string; p_role?: string; p_tribe_id: number }
        Returns: Json
      }
      admin_remove_tribe_selection: {
        Args: { p_member_id: string }
        Returns: Json
      }
      admin_resolve_anomaly: {
        Args: { p_anomaly_id: string; p_notes: string }
        Returns: Json
      }
      admin_restore_board_item: {
        Args: {
          p_item_id: string
          p_reason?: string
          p_restore_status?: string
        }
        Returns: Json
      }
      admin_restore_project_board: {
        Args: { p_board_id: string; p_reason?: string }
        Returns: Json
      }
      admin_retry_application_ai_analysis: {
        Args: { p_application_id: string }
        Returns: Json
      }
      admin_run_portfolio_data_sanity: { Args: never; Returns: Json }
      admin_run_retention_cleanup: { Args: never; Returns: Json }
      admin_send_campaign: {
        Args: {
          p_audience_filter?: Json
          p_external_contacts?: Json
          p_scheduled_at?: string
          p_template_id: string
        }
        Returns: Json
      }
      admin_set_ingestion_source_policy: {
        Args: {
          p_allow_apply: boolean
          p_notes: string
          p_require_manual_review: boolean
          p_source: string
        }
        Returns: Json
      }
      admin_set_ingestion_source_sla: {
        Args: {
          p_enabled?: boolean
          p_escalation_severity?: string
          p_expected_max_minutes?: number
          p_source: string
          p_timeout_minutes?: number
        }
        Returns: Json
      }
      admin_set_release_readiness_policy: {
        Args: {
          p_max_open_warnings?: number
          p_mode?: string
          p_policy_key?: string
          p_require_fresh_snapshot_hours?: number
        }
        Returns: Json
      }
      admin_set_tribe_active: {
        Args: { p_is_active: boolean; p_reason: string; p_tribe_id: number }
        Returns: Json
      }
      admin_start_ingestion_batch: {
        Args: { p_mode: string; p_notes: string; p_source: string }
        Returns: string
      }
      admin_update_application: {
        Args: { p_application_id: string; p_data: Json }
        Returns: Json
      }
      admin_update_board_columns: {
        Args: { p_board_id: string; p_columns: Json }
        Returns: Json
      }
      admin_update_member: {
        Args: {
          p_chapter?: string
          p_current_cycle_active?: boolean
          p_designations?: string[]
          p_email?: string
          p_linkedin_url?: string
          p_member_id: string
          p_name?: string
          p_operational_role?: string
          p_phone?: string
          p_pmi_id?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      admin_update_member_audited: {
        Args: { p_changes: Json; p_member_id: string }
        Returns: Json
      }
      admin_update_partner_status: {
        Args: { p_new_status: string; p_notes?: string; p_partner_id: string }
        Returns: Json
      }
      admin_update_setting: {
        Args: { p_key: string; p_new_value: Json; p_reason: string }
        Returns: Json
      }
      admin_upsert_legacy_tribe: {
        Args: {
          p_chapter: string
          p_cycle_code: string
          p_cycle_label: string
          p_display_name: string
          p_id: number
          p_legacy_key: string
          p_metadata: Json
          p_notes: string
          p_quadrant: number
          p_status: string
          p_tribe_id: number
        }
        Returns: Json
      }
      admin_upsert_tribe: {
        Args: {
          p_drive_url: string
          p_id: number
          p_is_active: boolean
          p_leader_member_id: string
          p_meeting_link: string
          p_miro_url: string
          p_name: string
          p_notes: string
          p_quadrant: number
          p_quadrant_name: string
          p_whatsapp_url: string
        }
        Returns: Json
      }
      admin_upsert_tribe_continuity_override: {
        Args: {
          p_continuity_key: string
          p_continuity_type: string
          p_current_cycle_code: string
          p_current_tribe_id: number
          p_is_active: boolean
          p_leader_name: string
          p_legacy_cycle_code: string
          p_legacy_tribe_id: number
          p_metadata: Json
          p_notes: string
        }
        Returns: Json
      }
      admin_upsert_tribe_lineage: {
        Args: {
          p_current_tribe_id: number
          p_cycle_scope: string
          p_id: number
          p_is_active: boolean
          p_legacy_tribe_id: number
          p_metadata: Json
          p_notes: string
          p_relation_type: string
        }
        Returns: Json
      }
      advance_approval_gate: {
        Args: { p_chain_id: string; p_reason?: string; p_target_status: string }
        Returns: Json
      }
      advance_board_item_curation: {
        Args: { p_action: string; p_item_id: string; p_reviewer_id?: string }
        Returns: undefined
      }
      advance_idea_stage: {
        Args: {
          p_idea_id: string
          p_new_stage: string
          p_notes?: string
          p_review_sub_stage?: string
        }
        Returns: Json
      }
      analytics_is_leadership_role: {
        Args: { p_designations: string[]; p_operational_role: string }
        Returns: boolean
      }
      analytics_role_bucket: {
        Args: { p_designations: string[]; p_operational_role: string }
        Returns: string
      }
      analyze_application_video: {
        Args: { p_application_id: string; p_force?: boolean; p_pillar?: string }
        Returns: Json
      }
      analyze_application_video_async: {
        Args: { p_application_id: string; p_force?: boolean; p_pillar?: string }
        Returns: Json
      }
      anonymize_application_for_ai_training: {
        Args: { p_application_id: string }
        Returns: Json
      }
      anonymize_by_engagement_kind: {
        Args: { p_dry_run?: boolean; p_limit?: number }
        Returns: Json
      }
      anonymize_inactive_members: {
        Args: { p_dry_run?: boolean; p_limit?: number; p_years?: number }
        Returns: Json
      }
      approve_change_request: {
        Args: {
          p_action: string
          p_comment?: string
          p_cr_id: string
          p_ip?: unknown
          p_user_agent?: string
        }
        Returns: Json
      }
      approve_selection_application: {
        Args: { p_application_id: string; p_decision?: Json }
        Returns: Json
      }
      assert_initiative_capability: {
        Args: { p_capability: string; p_initiative_id: string }
        Returns: undefined
      }
      assign_checklist_item: {
        Args: {
          p_assigned_to: string
          p_checklist_item_id: string
          p_target_date?: string
        }
        Returns: undefined
      }
      assign_curation_reviewer: {
        Args: { p_item_id: string; p_reviewer_id: string; p_round?: number }
        Returns: undefined
      }
      assign_event_tags: {
        Args: { p_event_id: string; p_tag_ids: string[] }
        Returns: undefined
      }
      assign_member_to_item: {
        Args: { p_item_id: string; p_member_id: string; p_role?: string }
        Returns: string
      }
      auth_org: { Args: never; Returns: string }
      auto_archive_done_cards: { Args: never; Returns: Json }
      auto_detect_onboarding_completions: { Args: never; Returns: undefined }
      auto_generate_cr_for_partnership: {
        Args: { p_partner_entity_id: string }
        Returns: Json
      }
      auto_promote_eligible_leads_daily: { Args: never; Returns: Json }
      auto_promote_eligible_leads_for_cycle: {
        Args: { p_cycle_id: string }
        Returns: Json
      }
      award_champion: {
        Args: {
          p_context_id: string
          p_context_kind: string
          p_criteria_met: string[]
          p_justification: string
          p_recipient_id: string
          p_surface: string
        }
        Returns: Json
      }
      broadcast_history: {
        Args: { p_limit?: number; p_tribe_id?: number }
        Returns: {
          id: string
          recipient_count: number
          sent_at: string
          sent_by_name: string
          subject: string
          tribe_id: number
          tribe_name: string
        }[]
      }
      bulk_issue_certificates: {
        Args: {
          p_cycle: number
          p_language: string
          p_member_ids: string[]
          p_period_end: string
          p_period_start: string
          p_title: string
          p_type: string
        }
        Returns: Json
      }
      bulk_mark_excused: {
        Args: {
          p_date_from: string
          p_date_to: string
          p_member_id: string
          p_override_existing?: boolean
          p_reason?: string
        }
        Returns: Json
      }
      calc_attendance_pct: { Args: never; Returns: number }
      calc_trail_completion_pct: { Args: never; Returns: number }
      calculate_rankings: { Args: { p_cycle_id: string }; Returns: Json }
      campaign_send_one_off: {
        Args: {
          p_metadata?: Json
          p_template_slug: string
          p_to_email: string
          p_variables?: Json
        }
        Returns: Json
      }
      can: {
        Args: {
          p_action: string
          p_person_id: string
          p_resource_id?: string
          p_resource_type?: string
        }
        Returns: boolean
      }
      can_by_member: {
        Args: {
          p_action: string
          p_member_id: string
          p_resource_id?: string
          p_resource_type?: string
        }
        Returns: boolean
      }
      can_manage_comms_metrics: { Args: never; Returns: boolean }
      can_manage_knowledge: { Args: never; Returns: boolean }
      can_read_internal_analytics: { Args: never; Returns: boolean }
      cancel_event_occurrence: {
        Args: { p_event_id: string; p_reason?: string }
        Returns: Json
      }
      cancel_manual_version_proposal: {
        Args: { p_proposal_id: string; p_reason?: string }
        Returns: Json
      }
      cancel_re_engagement: {
        Args: { p_pipeline_id: string; p_reason?: string }
        Returns: Json
      }
      capture_vep_baseline: {
        Args: { p_label: string; p_notes?: string }
        Returns: Json
      }
      capture_visitor_lead: { Args: { p_payload: Json }; Returns: Json }
      check_application_score_consistency: {
        Args: never
        Returns: {
          application_id: string
          cached: number
          computed: number
          drift: number
          evaluation_type: string
          n_evals: number
        }[]
      }
      check_code_schema_drift: {
        Args: never
        Returns: {
          object_name: string
          object_type: string
          pattern_matched: string
          reason: string
          schema_name: string
          suspect_reference: string
        }[]
      }
      check_my_privacy_status: { Args: never; Returns: Json }
      check_my_tcv_readiness: { Args: never; Returns: Json }
      check_pre_onboarding_auto_steps: {
        Args: { p_member_id: string }
        Returns: Json
      }
      check_schema_invariants: {
        Args: never
        Returns: {
          description: string
          invariant_name: string
          sample_ids: string[]
          severity: string
          violation_count: number
        }[]
      }
      comms_acknowledge_alert: { Args: { p_alert_id: string }; Returns: Json }
      comms_channel_status: { Args: never; Returns: Json }
      comms_check_token_expiry: { Args: never; Returns: Json }
      comms_executive_kpis: { Args: never; Returns: Json }
      comms_metrics_latest_by_channel: {
        Args: { p_days?: number }
        Returns: {
          audience: number
          channel: string
          engagement: number
          leads: number
          metric_date: string
          payload: Json
          reach: number
          source: string
          updated_at: string
        }[]
      }
      comms_top_media: {
        Args: { p_channel?: string; p_days?: number; p_limit?: number }
        Returns: Json
      }
      complete_checklist_item: {
        Args: { p_checklist_item_id: string; p_completed?: boolean }
        Returns: undefined
      }
      complete_leader_review: {
        Args: { p_decision: string; p_item_id: string; p_notes?: string }
        Returns: undefined
      }
      complete_onboarding_step: {
        Args: { p_metadata?: Json; p_step_id: string }
        Returns: Json
      }
      complete_peer_review: {
        Args: {
          p_item_id: string
          p_summary?: string
          p_waived?: boolean
          p_waiver_reason?: string
        }
        Returns: undefined
      }
      compute_ai_calibration_stats: {
        Args: { p_cycle_id: string; p_drift_threshold?: number }
        Returns: Json
      }
      compute_ai_calibration_weekly: { Args: never; Returns: Json }
      compute_application_scores: {
        Args: { p_application_id: string }
        Returns: Json
      }
      compute_legacy_role: {
        Args: { p_desigs: string[]; p_op_role: string }
        Returns: string
      }
      compute_legacy_roles: {
        Args: { p_desigs: string[]; p_op_role: string }
        Returns: string[]
      }
      compute_pert_cutoff: {
        Args: {
          p_cycle_id: string
          p_filter_active_only?: boolean
          p_role?: string
          p_score_column?: string
        }
        Returns: Json
      }
      confirm_manual_version: { Args: { p_proposal_id: string }; Returns: Json }
      confirm_secondary_email: { Args: { p_token: string }; Returns: Json }
      consume_onboarding_token: { Args: { p_token: string }; Returns: Json }
      convert_action_to_card: {
        Args: {
          p_action_item_id: string
          p_board_id: string
          p_description?: string
          p_due_date?: string
          p_status?: string
          p_title?: string
        }
        Returns: Json
      }
      convert_proposal_to_webinar: {
        Args: {
          p_chapter_code: string
          p_duration_min?: number
          p_initiative_id?: string
          p_proposal_id: string
          p_scheduled_at: string
        }
        Returns: Json
      }
      count_tribe_slots: { Args: never; Returns: Json }
      counter_sign_certificate: {
        Args: {
          p_certificate_id: string
          p_signed_ip?: string
          p_signed_user_agent?: string
        }
        Returns: Json
      }
      create_action_item: {
        Args: {
          p_assignee_id?: string
          p_board_item_id?: string
          p_checklist_item_id?: string
          p_description: string
          p_due_date?: string
          p_event_id: string
          p_kind?: string
        }
        Returns: Json
      }
      create_board_item: {
        Args: {
          p_assignee_id?: string
          p_board_id: string
          p_description?: string
          p_due_date?: string
          p_status?: string
          p_tags?: string[]
          p_title: string
        }
        Returns: string
      }
      create_card_comment: {
        Args: {
          p_board_item_id: string
          p_body: string
          p_mentioned_member_ids?: string[]
          p_parent_comment_id?: string
        }
        Returns: Json
      }
      create_change_note: {
        Args: { p_body: string; p_chain_id: string }
        Returns: Json
      }
      create_cost_entry: {
        Args: {
          p_amount_brl: number
          p_category_name: string
          p_date: string
          p_description: string
          p_event_id?: string
          p_notes?: string
          p_paid_by?: string
          p_submission_id?: string
        }
        Returns: string
      }
      create_document_comment: {
        Args: {
          p_body: string
          p_clause_anchor: string
          p_parent_id?: string
          p_version_id: string
          p_visibility: string
        }
        Returns: Json
      }
      create_event: {
        Args: {
          p_agenda_text?: string
          p_agenda_url?: string
          p_audience_level?: string
          p_date: string
          p_duration_minutes?: number
          p_external_attendees?: string[]
          p_invited_member_ids?: string[]
          p_meeting_link?: string
          p_nature?: string
          p_time_start?: string
          p_title: string
          p_tribe_id?: number
          p_type: string
          p_visibility?: string
        }
        Returns: Json
      }
      create_external_signer_invite: {
        Args: {
          p_chapter_code?: string
          p_email: string
          p_name: string
          p_organization: string
          p_relationship: string
        }
        Returns: Json
      }
      create_external_speaker_engagement: {
        Args: {
          p_board_domain_key?: string
          p_co_person_id?: string
          p_deadlines?: Json
          p_drive_folder_url?: string
          p_initiative_description?: string
          p_initiative_kind?: string
          p_initiative_title: string
          p_lead_person_id: string
          p_meeting_link?: string
          p_org_id?: string
          p_partner_entity_id: string
          p_whatsapp_url?: string
        }
        Returns: Json
      }
      create_initiative: {
        Args: {
          p_description?: string
          p_kind: string
          p_metadata?: Json
          p_parent_initiative_id?: string
          p_title: string
        }
        Returns: string
      }
      create_initiative_event: {
        Args: {
          p_date: string
          p_duration_minutes?: number
          p_initiative_id: string
          p_meeting_link?: string
          p_time_start?: string
          p_title: string
          p_type?: string
        }
        Returns: Json
      }
      create_initiative_invitations: {
        Args: {
          p_initiative_id: string
          p_invitee_member_ids: string[]
          p_kind_scope: string
          p_message: string
        }
        Returns: Json
      }
      create_mirror_card: {
        Args: {
          p_notes?: string
          p_source_item_id: string
          p_target_board_id: string
          p_target_status?: string
        }
        Returns: string
      }
      create_next_geral_meeting: {
        Args: {
          p_interval_days?: number
          p_meeting_link: string
          p_title?: string
          p_youtube_url?: string
        }
        Returns: Json
      }
      create_notification:
        | {
            Args: {
              p_actor_id?: string
              p_recipient_id: string
              p_source_id?: string
              p_source_title?: string
              p_source_type?: string
              p_type: string
            }
            Returns: string
          }
        | {
            Args: {
              p_actor_id: string
              p_body?: string
              p_recipient_id: string
              p_source_id: string
              p_source_title: string
              p_source_type: string
              p_type: string
            }
            Returns: string
          }
        | {
            Args: {
              p_body?: string
              p_link?: string
              p_recipient_id: string
              p_source_id?: string
              p_source_type?: string
              p_title: string
              p_type: string
            }
            Returns: undefined
          }
      create_pilot: {
        Args: {
          p_board_id?: string
          p_hypothesis?: string
          p_problem_statement?: string
          p_scope?: string
          p_status?: string
          p_success_metrics?: Json
          p_team_member_ids?: string[]
          p_title: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      create_publication_submission: {
        Args: {
          p_abstract?: string
          p_board_item_id?: string
          p_estimated_cost_brl?: number
          p_primary_author_id: string
          p_target_name: string
          p_target_type: Database["public"]["Enums"]["submission_target_type"]
          p_target_url?: string
          p_title: string
          p_tribe_id?: number
        }
        Returns: string
      }
      create_recurring_weekly_events: {
        Args: {
          p_audience_level?: string
          p_duration_minutes?: number
          p_is_recorded?: boolean
          p_meeting_link?: string
          p_n_weeks?: number
          p_start_date: string
          p_time_start?: string
          p_title_template: string
          p_tribe_id?: number
          p_type: string
        }
        Returns: Json
      }
      create_revenue_entry: {
        Args: {
          p_amount_brl?: number
          p_category_name: string
          p_date: string
          p_description: string
          p_notes?: string
          p_value_type?: string
        }
        Returns: string
      }
      create_tag: {
        Args: {
          p_color?: string
          p_description?: string
          p_domain?: string
          p_label_pt: string
          p_name: string
          p_tier?: string
        }
        Returns: string
      }
      create_webinar_proposal: {
        Args: {
          p_format_type: string
          p_notes?: string
          p_proposed_by_tribe_id?: number
          p_proposed_speakers?: string[]
          p_proposed_title: string
          p_quadrant_anchor?: number
          p_series_id?: string
          p_themes?: string[]
        }
        Returns: Json
      }
      curate_item: {
        Args: {
          p_action: string
          p_audience_level?: string
          p_id: string
          p_table: string
          p_tags?: string[]
          p_tribe_id?: number
        }
        Returns: Json
      }
      decrypt_sensitive: { Args: { val: string }; Returns: string }
      delete_board_item: {
        Args: { p_item_id: string; p_reason?: string }
        Returns: undefined
      }
      delete_card_comment: { Args: { p_comment_id: string }; Returns: Json }
      delete_checklist_item: {
        Args: { p_checklist_item_id: string; p_reason?: string }
        Returns: undefined
      }
      delete_cost_entry: { Args: { p_id: string }; Returns: undefined }
      delete_document_version_draft: {
        Args: { p_version_id: string }
        Returns: Json
      }
      delete_my_personal_data: {
        Args: { p_confirm_text?: string }
        Returns: Json
      }
      delete_partner_attachment: {
        Args: { p_attachment_id: string }
        Returns: Json
      }
      delete_pilot: { Args: { p_id: string }; Returns: Json }
      delete_revenue_entry: { Args: { p_id: string }; Returns: undefined }
      delete_tag: { Args: { p_tag_id: string }; Returns: undefined }
      deselect_tribe: { Args: never; Returns: Json }
      detect_and_notify_detractors: { Args: never; Returns: Json }
      detect_and_notify_detractors_cron: { Args: never; Returns: Json }
      detect_inactive_members: { Args: { p_dry_run?: boolean }; Returns: Json }
      detect_mcp_anomalies: {
        Args: never
        Returns: {
          count: number
          inserted: boolean
          member_id: string
          pattern: string
          tool_name: string
        }[]
      }
      detect_onboarding_overdue: { Args: never; Returns: Json }
      detect_operational_alerts: { Args: never; Returns: Json }
      detect_orphan_assignees_from_offboards: {
        Args: { p_member_id?: string }
        Returns: number
      }
      detect_stale_events_cron: { Args: never; Returns: Json }
      detect_stale_portfolio_items_cron: { Args: never; Returns: Json }
      dismiss_onboarding: { Args: never; Returns: undefined }
      dismiss_visitor_lead: {
        Args: { p_lead_id: string; p_reason?: string }
        Returns: Json
      }
      dispatch_consent_nudge: {
        Args: { p_dry_run?: boolean; p_max_count?: number; p_ttl_days?: number }
        Returns: Json
      }
      dispatch_peer_review_invitations: {
        Args: { p_application_id: string; p_max_peers?: number }
        Returns: Json
      }
      dispatch_pending_welcomes: {
        Args: { p_dry_run?: boolean; p_max_count?: number; p_ttl_days?: number }
        Returns: Json
      }
      drop_event_instance: {
        Args: { p_event_id: string; p_force_delete_attendance?: boolean }
        Returns: Json
      }
      duplicate_board_item: {
        Args: { p_item_id: string; p_target_board_id?: string }
        Returns: string
      }
      encrypt_sensitive: { Args: { val: string }; Returns: string }
      enrich_applications_from_csv: {
        Args: {
          p_cycle_id: string
          p_opportunity_id: string
          p_rows: Json
          p_snapshot_date?: string
        }
        Returns: Json
      }
      enroll_in_cpmai_course: {
        Args: {
          p_ai_experience?: string
          p_course_id: string
          p_domains_of_interest?: number[]
          p_motivation?: string
        }
        Returns: Json
      }
      exec_all_tribes_summary: { Args: never; Returns: Json }
      exec_cert_timeline: {
        Args: { p_months?: number }
        Returns: {
          avg_days_to_tier1: number
          avg_days_to_tier2: number
          cohort_month: string
          members_in_cohort: number
          members_with_tier1: number
          members_with_tier2: number
          pct_with_tier1: number
          pct_with_tier2: number
        }[]
      }
      exec_chapter_comparison: { Args: never; Returns: Json }
      exec_chapter_dashboard: { Args: { p_chapter: string }; Returns: Json }
      exec_cross_initiative_comparison: {
        Args: { p_cycle?: string; p_kind?: string }
        Returns: Json
      }
      exec_cycle_report: { Args: { p_cycle_code?: string }; Returns: Json }
      exec_initiative_dashboard: {
        Args: { p_cycle?: string; p_initiative_id: string }
        Returns: Json
      }
      exec_portfolio_board_summary: {
        Args: { p_include_inactive?: boolean }
        Returns: Json
      }
      exec_portfolio_health: { Args: { p_cycle_code?: string }; Returns: Json }
      exec_role_transitions: {
        Args: { p_chapter?: string; p_cycle_code?: string; p_tribe_id?: number }
        Returns: Json
      }
      exec_skills_radar: { Args: never; Returns: Json }
      exec_tribe_dashboard: {
        Args: { p_cycle?: string; p_tribe_id: number }
        Returns: Json
      }
      expire_stale_initiative_invitations: { Args: never; Returns: Json }
      export_audit_log_csv: {
        Args: {
          p_category?: string
          p_end_date?: string
          p_start_date?: string
        }
        Returns: string
      }
      export_my_data: { Args: never; Returns: Json }
      extract_cv_text_batch: { Args: { p_limit?: number }; Returns: Json }
      finalize_decisions: {
        Args: { p_cycle_id: string; p_decisions: Json }
        Returns: Json
      }
      fork_idea_to_channel: {
        Args: { p_channel: string; p_idea_id: string; p_payload_hint?: Json }
        Returns: Json
      }
      generate_agenda_template: { Args: { p_tribe_id: number }; Returns: Json }
      generate_weekly_card_digest_cron: {
        Args: never
        Returns: {
          member_id: string
          notified: boolean
          reason: string
        }[]
      }
      generate_weekly_leader_digest_cron: {
        Args: never
        Returns: {
          batch_id: string
          initiative_id: string
          initiative_name: string
          leader_id: string
          notified: boolean
          reason: string
        }[]
      }
      generate_weekly_member_digest_cron: {
        Args: never
        Returns: {
          batch_id: string
          member_id: string
          notified: boolean
          reason: string
        }[]
      }
      get_active_chapters: {
        Args: never
        Returns: {
          chapter_code: string
          country: string
          display_code: string
          display_order: number
          is_contracting: boolean
          legal_name: string
          logo_url: string
          state: string
        }[]
      }
      get_active_engagements: { Args: { p_person_id?: string }; Returns: Json }
      get_admin_dashboard: { Args: never; Returns: Json }
      get_adoption_dashboard: { Args: never; Returns: Json }
      get_agenda_smart: { Args: { p_event_id: string }; Returns: Json }
      get_ai_suggestion: {
        Args: { p_application_id: string; p_evaluation_type: string }
        Returns: Json
      }
      get_all_certificates: {
        Args: {
          p_include_volunteer_agreements?: boolean
          p_search?: string
          p_status_filter?: string
        }
        Returns: Json
      }
      get_annual_kpis: {
        Args: { p_cycle?: number; p_year?: number }
        Returns: Json
      }
      get_application_ai_analysis_runs: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_application_communications: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_application_enrichment_status: {
        Args: { p_token: string }
        Returns: Json
      }
      get_application_gate_attempts: {
        Args: { p_application_id: string }
        Returns: {
          attempt_id: string
          attempted_at: string
          bypass_granted: boolean
          bypass_requested: boolean
          caller_name: string
          gate_failed_code: string
          gate_failed_reason: string
          gate_passed: boolean
          payload: Json
          rpc_name: string
        }[]
      }
      get_application_interviews: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_application_onboarding_pct: {
        Args: { p_application_id: string }
        Returns: number
      }
      get_application_pmi_profile: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_application_returning_context: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_application_score_breakdown: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_application_video_screenings: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_attendance_grid: {
        Args: { p_event_type?: string; p_tribe_id?: number }
        Returns: Json
      }
      get_attendance_panel: {
        Args: { p_cycle_end?: string; p_cycle_start?: string }
        Returns: {
          combined_pct: number
          dropout_risk: boolean
          general_attended: number
          general_mandatory: number
          general_pct: number
          last_attendance: string
          member_id: string
          member_name: string
          operational_role: string
          tribe_attended: number
          tribe_id: number
          tribe_mandatory: number
          tribe_name: string
          tribe_pct: number
          typology: string
        }[]
      }
      get_attendance_summary: {
        Args: {
          p_cycle_end?: string
          p_cycle_start?: string
          p_tribe_id?: number
        }
        Returns: {
          combined_pct: number
          consecutive_misses: number
          geral_pct: number
          geral_present: number
          geral_total: number
          last_attendance: string
          member_id: string
          member_name: string
          operational_role: string
          tribe_id: number
          tribe_name: string
          tribe_pct: number
          tribe_present: number
          tribe_total: number
        }[]
      }
      get_audit_log: {
        Args: {
          p_action?: string
          p_actor_id?: string
          p_date_from?: string
          p_date_to?: string
          p_limit?: number
          p_offset?: number
          p_target_id?: string
        }
        Returns: Json
      }
      get_auth_provider_stats: { Args: never; Returns: Json }
      get_blog_likes_batch: { Args: { p_post_ids: string[] }; Returns: Json }
      get_blog_post_likes: { Args: { p_post_id: string }; Returns: Json }
      get_board: { Args: { p_board_id: string }; Returns: Json }
      get_board_activities:
        | { Args: { p_board_id?: string; p_limit?: number }; Returns: Json }
        | {
            Args: {
              p_assignee_filter?: string
              p_board_id: string
              p_period_filter?: string
              p_status_filter?: string
            }
            Returns: Json
          }
      get_board_by_domain: {
        Args: {
          p_domain_key: string
          p_initiative_id?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      get_board_drive_links: { Args: { p_board_id: string }; Returns: Json }
      get_board_members: {
        Args: { p_board_id: string }
        Returns: {
          board_role: string
          designations: string[]
          id: string
          name: string
          operational_role: string
          photo_url: string
        }[]
      }
      get_board_tags: { Args: { p_board_id: string }; Returns: Json }
      get_board_timeline: { Args: { p_board_id: string }; Returns: Json }
      get_caller_capabilities: { Args: never; Returns: Json }
      get_campaign_analytics: { Args: { p_send_id?: string }; Returns: Json }
      get_candidate_onboarding_progress: {
        Args: { p_member_id?: string }
        Returns: Json
      }
      get_card_detail: { Args: { p_card_id: string }; Returns: Json }
      get_card_full_history: { Args: { p_card_id: string }; Returns: Json }
      get_card_timeline: {
        Args: { p_item_id: string }
        Returns: {
          action: string
          actor_name: string
          created_at: string
          id: number
          new_status: string
          previous_status: string
          reason: string
          review_round: number
          review_score: Json
          sla_deadline: string
        }[]
      }
      get_chain_audit_report: { Args: { p_chain_id: string }; Returns: Json }
      get_chain_for_pdf: { Args: { p_chain_id: string }; Returns: Json }
      get_chain_workflow_detail: { Args: { p_chain_id: string }; Returns: Json }
      get_champion_criteria_for_surface: {
        Args: { p_surface: string }
        Returns: {
          display_name_i18n: Json
          slug: string
          sort_order: number
        }[]
      }
      get_champions_ranking: {
        Args: {
          p_cycle_code?: string
          p_limit?: number
          p_scope_id?: string
          p_scope_kind?: string
        }
        Returns: Json
      }
      get_change_requests: {
        Args: { p_cr_type: string; p_status: string }
        Returns: Json
      }
      get_changelog: { Args: never; Returns: Json }
      get_chapter_dashboard: { Args: { p_chapter?: string }; Returns: Json }
      get_chapter_needs: {
        Args: { p_chapter?: string }
        Returns: {
          admin_notes: string
          category: string
          chapter: string
          created_at: string
          description: string
          id: string
          status: string
          submitted_by_name: string
          title: string
          updated_at: string
        }[]
      }
      get_comms_dashboard_metrics: { Args: never; Returns: Json }
      get_comms_pipeline: { Args: never; Returns: Json }
      get_comms_to_adoption_funnel: {
        Args: { p_period_days?: number }
        Returns: Json
      }
      get_communication_template: {
        Args: { p_slug: string; p_vars?: Json }
        Returns: Json
      }
      get_cost_entries: {
        Args: {
          p_category_name?: string
          p_date_from?: string
          p_date_to?: string
          p_limit?: number
        }
        Returns: {
          amount_brl: number
          category_description: string
          category_name: string
          created_at: string
          created_by_name: string
          date: string
          description: string
          event_title: string
          id: string
          notes: string
          paid_by: string
          submission_title: string
        }[]
      }
      get_cpmai_admin_dashboard: {
        Args: { p_course_id?: string }
        Returns: Json
      }
      get_cpmai_course_dashboard: {
        Args: { p_course_id?: string }
        Returns: Json
      }
      get_cpmai_leaderboard: { Args: { p_course_id?: string }; Returns: Json }
      get_cr_approval_status: { Args: { p_cr_id: string }; Returns: Json }
      get_cron_status: { Args: never; Returns: Json }
      get_curation_cross_board: { Args: never; Returns: Json }
      get_curation_dashboard: { Args: never; Returns: Json }
      get_current_cycle: { Args: never; Returns: Json }
      get_current_release: { Args: never; Returns: Json }
      get_cycle_evolution: { Args: never; Returns: Json }
      get_cycle_report: { Args: { p_cycle?: number }; Returns: Json }
      get_decision_log: {
        Args: { p_filter?: string }
        Returns: {
          id: string
          path: string
          summary: string
          tags: string[]
          title: string
          updated_at: string
        }[]
      }
      get_digest_health: { Args: never; Returns: Json }
      get_diversity_dashboard: { Args: { p_cycle_id?: string }; Returns: Json }
      get_document_detail: { Args: { p_document_id: string }; Returns: Json }
      get_drive_discovery_health: { Args: never; Returns: Json }
      get_dropout_risk_members: {
        Args: { p_threshold?: number }
        Returns: {
          days_since_last: number
          last_attendance_date: string
          member_id: string
          member_name: string
          missed_events: number
          operational_role: string
          tribe_id: number
          tribe_name: string
        }[]
      }
      get_dual_track_merged_payload: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_essay_field: {
        Args: { p_index: string; p_mapping: Json }
        Returns: string
      }
      get_evaluation_form: {
        Args: { p_application_id: string; p_evaluation_type: string }
        Returns: Json
      }
      get_evaluation_results: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_evaluator_calibration_stats: {
        Args: { p_cycle_code?: string }
        Returns: Json
      }
      get_event_attendance_health: { Args: never; Returns: Json }
      get_event_audience: {
        Args: { p_event_id: string }
        Returns: {
          attendance_type: string
          invited_members: Json
          rule_id: string
          target_type: string
          target_value: string
        }[]
      }
      get_event_champion_suggestions: {
        Args: { p_event_id: string }
        Returns: {
          designation_summary: string
          member_id: string
          member_name: string
        }[]
      }
      get_event_detail: { Args: { p_event_id: string }; Returns: Json }
      get_event_tags: {
        Args: { p_event_id: string }
        Returns: {
          color: string
          label_pt: string
          tag_id: string
          tag_name: string
          tier: Database["public"]["Enums"]["tag_tier"]
        }[]
      }
      get_event_tags_batch: {
        Args: { p_event_ids: string[] }
        Returns: {
          color: string
          event_id: string
          label_pt: string
          tag_id: string
          tag_name: string
          tier: Database["public"]["Enums"]["tag_tier"]
        }[]
      }
      get_events_with_attendance: {
        Args: { p_limit?: number; p_offset?: number }
        Returns: {
          agenda_text: string
          agenda_url: string
          attendee_count: number
          audience_level: string
          cancellation_reason: string
          cancelled_at: string
          date: string
          duration_minutes: number
          external_attendees: string[]
          id: string
          initiative_id: string
          initiative_name: string
          is_recorded: boolean
          meeting_link: string
          minutes_text: string
          minutes_url: string
          nature: string
          notes: string
          recording_type: string
          recording_url: string
          recurrence_group: string
          status: string
          time_start: string
          title: string
          tribe_id: number
          type: string
          visibility: string
          youtube_url: string
        }[]
      }
      get_executive_kpis: { Args: never; Returns: Json }
      get_extraction_health: { Args: never; Returns: Json }
      get_gamification_category_activity: {
        Args: { p_window_days?: number }
        Returns: {
          active: boolean
          base_points: number
          display_name: string
          is_orphan: boolean
          last_7d_events: number
          last_award: string
          last_window_events: number
          pillar: string
          slug: string
          status: string
          total_events: number
          trigger_source: string
          unique_members: number
        }[]
      }
      get_gamification_leaderboard: {
        Args: {
          p_chapter_code?: string
          p_cycle_code?: string
          p_initiative_id?: string
          p_limit?: number
          p_offset?: number
          p_scope_kind?: string
        }
        Returns: {
          artifact_points: number
          attendance_points: number
          badge_points: number
          bonus_points: number
          cert_points: number
          champions_points: number
          chapter: string
          course_points: number
          curadoria_points: number
          cycle_artifact_points: number
          cycle_attendance_points: number
          cycle_badge_points: number
          cycle_bonus_points: number
          cycle_cert_points: number
          cycle_champions_points: number
          cycle_course_points: number
          cycle_curadoria_points: number
          cycle_learning_points: number
          cycle_points: number
          cycle_producao_points: number
          cycle_showcase_points: number
          designations: string[]
          learning_points: number
          member_id: string
          name: string
          operational_role: string
          photo_url: string
          producao_points: number
          showcase_points: number
          total_count: number
          total_points: number
        }[]
      }
      get_ghost_visitors: {
        Args: never
        Returns: {
          out_auth_id: string
          out_created_at: string
          out_email: string
          out_last_sign_in_at: string
          out_possible_member_name: string
          out_provider: string
        }[]
      }
      get_global_research_pipeline: { Args: never; Returns: Json }
      get_governance_change_log: {
        Args: {
          p_include_payload?: boolean
          p_limit?: number
          p_since?: string
        }
        Returns: {
          actor_id: string
          actor_name: string
          event_kind: string
          event_source: string
          event_time: string
          payload: Json
          target_id: string
          target_label: string
          target_type: string
        }[]
      }
      get_governance_dashboard: { Args: never; Returns: Json }
      get_governance_documents: { Args: { p_doc_type: string }; Returns: Json }
      get_governance_glossary: { Args: never; Returns: Json }
      get_governance_preview: { Args: never; Returns: Json }
      get_governance_stats: { Args: never; Returns: Json }
      get_gp_whatsapp: { Args: never; Returns: Json }
      get_help_journeys: { Args: never; Returns: Json }
      get_homepage_stats: { Args: never; Returns: Json }
      get_idea_pipeline: {
        Args: {
          p_series_id?: string
          p_stage_filter?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      get_impact_hours_canonical: {
        Args: { p_end_date?: string; p_start_date?: string }
        Returns: number
      }
      get_impact_hours_excluding_excused: { Args: never; Returns: number }
      get_in_dashboard: { Args: never; Returns: Json }
      get_initiative_attendance_grid: {
        Args: { p_event_type?: string; p_initiative_id: string }
        Returns: Json
      }
      get_initiative_board_summary: {
        Args: { p_initiative_id: string }
        Returns: Json
      }
      get_initiative_detail: {
        Args: { p_initiative_id: string }
        Returns: Json
      }
      get_initiative_drive_links: {
        Args: { p_initiative_id: string }
        Returns: Json
      }
      get_initiative_events_timeline: {
        Args: {
          p_initiative_id: string
          p_past_limit?: number
          p_upcoming_limit?: number
        }
        Returns: Json
      }
      get_initiative_gamification: {
        Args: { p_initiative_id: string }
        Returns: Json
      }
      get_initiative_member_contacts: {
        Args: { p_initiative_id: string }
        Returns: Json
      }
      get_initiative_members: {
        Args: { p_initiative_id: string }
        Returns: Json
      }
      get_initiative_stats: { Args: { p_initiative_id: string }; Returns: Json }
      get_invariant_alerts: { Args: never; Returns: Json }
      get_invitation_health: { Args: never; Returns: Json }
      get_item_assignments: { Args: { p_item_id: string }; Returns: Json }
      get_item_curation_history: { Args: { p_item_id: string }; Returns: Json }
      get_kpi_dashboard: {
        Args: { p_cycle_end?: string; p_cycle_start?: string }
        Returns: Json
      }
      get_lgpd_cron_health: { Args: never; Returns: Json }
      get_manual_diff: { Args: never; Returns: Json }
      get_manual_sections: { Args: { p_version?: string }; Returns: Json }
      get_mcp_adoption_stats: { Args: never; Returns: Json }
      get_meeting_detail: { Args: { p_event_id: string }; Returns: Json }
      get_meeting_notes_compliance: { Args: never; Returns: Json }
      get_meeting_preparation: { Args: { p_event_id: string }; Returns: Json }
      get_member_attendance_hours: {
        Args: { p_cycle_code?: string; p_member_id: string }
        Returns: {
          avg_hours_per_event: number
          current_streak: number
          total_events: number
          total_hours: number
        }[]
      }
      get_member_by_auth: { Args: never; Returns: Json }
      get_member_champions_history: {
        Args: { p_member_id?: string }
        Returns: Json
      }
      get_member_cycle_xp: { Args: { p_member_id: string }; Returns: Json }
      get_member_detail: { Args: { p_member_id: string }; Returns: Json }
      get_member_gamification_stats: {
        Args: { p_member_ids: string[] }
        Returns: {
          active_cycles_count: number
          current_streak_count: number
          longest_streak_count: number
          member_id: string
          points_this_cycle: number
        }[]
      }
      get_member_offboarding_record: {
        Args: { p_member_id: string }
        Returns: Json
      }
      get_member_transitions: { Args: { p_member_id: string }; Returns: Json }
      get_member_tribe: { Args: { p_member_id: string }; Returns: number }
      get_member_xp_pillars: {
        Args: { p_cycle_code?: string; p_member_id?: string; p_scope?: string }
        Returns: Json
      }
      get_mirror_target_boards: {
        Args: { p_source_board_id: string }
        Returns: {
          board_id: string
          board_name: string
          board_scope: string
          item_count: number
        }[]
      }
      get_my_application_status: { Args: never; Returns: Json }
      get_my_attendance_history: {
        Args: { p_limit?: number }
        Returns: {
          duration_minutes: number
          event_date: string
          event_id: string
          event_title: string
          event_type: string
          excused: boolean
          present: boolean
        }[]
      }
      get_my_cards: { Args: never; Returns: Json }
      get_my_certificates: {
        Args: { p_include_volunteer_agreements?: boolean }
        Returns: Json
      }
      get_my_committee_assignments: { Args: never; Returns: Json }
      get_my_credly_status: { Args: never; Returns: Json }
      get_my_evaluation_feedback: { Args: never; Returns: Json }
      get_my_gamification_stats: { Args: never; Returns: Json }
      get_my_member_record: {
        Args: never
        Returns: {
          designations: string[]
          id: string
          is_superadmin: boolean
          operational_role: string
          tribe_id: number
        }[]
      }
      get_my_notification_metrics: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      get_my_notifications: {
        Args: { p_limit?: number; p_unread_only?: boolean }
        Returns: Json
      }
      get_my_onboarding: { Args: never; Returns: Json }
      get_my_organization: { Args: never; Returns: Json }
      get_my_pending_evaluations: { Args: never; Returns: Json }
      get_my_pii_access_log: { Args: { p_limit?: number }; Returns: Json }
      get_my_quick_start_progress: { Args: never; Returns: Json }
      get_my_re_engagement_invitation: {
        Args: { p_pipeline_id: string }
        Returns: Json
      }
      get_my_selection_result: { Args: never; Returns: Json }
      get_my_signatures: {
        Args: { p_include_superseded?: boolean }
        Returns: Json
      }
      get_my_tasks: {
        Args: { p_period_filter?: string; p_status_filter?: string }
        Returns: Json
      }
      get_near_events: {
        Args: { p_member_id: string; p_window_hours?: number }
        Returns: {
          already_checked_in: boolean
          duration_minutes: number
          event_date: string
          event_id: string
          event_title: string
          event_type: string
        }[]
      }
      get_next_draft_version: { Args: { p_version_id: string }; Returns: Json }
      get_notification_count: { Args: never; Returns: number }
      get_notifications_analytics: {
        Args: { p_window_days?: number }
        Returns: Json
      }
      get_offboarding_dashboard: { Args: never; Returns: Json }
      get_onboarding_dashboard: { Args: never; Returns: Json }
      get_onboarding_status: {
        Args: { p_application_id: string }
        Returns: Json
      }
      get_org_chart: { Args: never; Returns: Json }
      get_partner_entity_attachments: {
        Args: { p_entity_id: string }
        Returns: Json
      }
      get_partner_followups: { Args: never; Returns: Json }
      get_partner_interaction_attachments: {
        Args: { p_interaction_id: string }
        Returns: Json
      }
      get_partner_interactions: {
        Args: { p_partner_id: string }
        Returns: Json
      }
      get_partner_pipeline: { Args: never; Returns: Json }
      get_pending_agreement_engagements: { Args: never; Returns: Json }
      get_pending_countersign: { Args: never; Returns: Json }
      get_pending_ratifications: {
        Args: never
        Returns: {
          chain_id: string
          doc_type: string
          document_id: string
          document_title: string
          eligible_gates: string[]
          gates: Json
          opened_at: string
          status: string
          version_id: string
          version_label: string
          version_locked_at: string
        }[]
      }
      get_person: { Args: { p_person_id?: string }; Returns: Json }
      get_pert_cutoff_summary:
        | { Args: { p_cycle_id: string }; Returns: Json }
        | {
            Args: { p_cycle_id: string; p_score_column?: string }
            Returns: Json
          }
      get_pii_access_log_admin: {
        Args: {
          p_accessor_id?: string
          p_days?: number
          p_limit?: number
          p_target_member_id?: string
        }
        Returns: Json
      }
      get_pilot_metrics: { Args: { p_pilot_id: string }; Returns: Json }
      get_pilots_summary: { Args: never; Returns: Json }
      get_platform_setting: { Args: { p_key: string }; Returns: Json }
      get_platform_usage: { Args: never; Returns: Json }
      get_pmi_launch_health: { Args: { p_cycle_code?: string }; Returns: Json }
      get_portfolio_dashboard: { Args: { p_cycle?: number }; Returns: Json }
      get_portfolio_items: {
        Args: { p_cycle_code?: string; p_status?: string; p_tribe_id?: number }
        Returns: {
          baseline_date: string
          baseline_locked_at: string
          cycle_code: string
          due_date: string
          forecast_date: string
          id: string
          initiative_id: string
          is_portfolio_item: boolean
          portfolio_kpi_refs: string[]
          status: string
          title: string
          tribe_id: number
          updated_at: string
        }[]
      }
      get_portfolio_planned_vs_actual: {
        Args: { p_cycle?: number }
        Returns: Json
      }
      get_portfolio_timeline: { Args: never; Returns: Json }
      get_pre_onboarding_leaderboard: { Args: never; Returns: Json }
      get_previous_locked_version: {
        Args: { p_version_id: string }
        Returns: Json
      }
      get_public_impact_data: { Args: never; Returns: Json }
      get_public_leaderboard: {
        Args: { p_limit?: number }
        Returns: {
          chapter: string
          level_name: string
          member_name: string
          rank_position: number
          tribe_name: string
          xp_total: number
        }[]
      }
      get_public_platform_stats: { Args: never; Returns: Json }
      get_public_publications: {
        Args: {
          p_cycle?: string
          p_limit?: number
          p_search?: string
          p_tribe_id?: number
          p_type?: string
        }
        Returns: Json
      }
      get_public_trail_ranking: {
        Args: never
        Returns: {
          completed: number
          in_progress: number
          member_name: string
          pct: number
          photo_url: string
        }[]
      }
      get_publication_detail: { Args: { p_id: string }; Returns: Json }
      get_publication_pipeline_summary: { Args: never; Returns: Json }
      get_publication_submission_detail: {
        Args: { p_submission_id: string }
        Returns: Json
      }
      get_publication_submissions: {
        Args: {
          p_status?: Database["public"]["Enums"]["submission_status"]
          p_tribe_id?: number
        }
        Returns: {
          abstract: string
          actual_cost_brl: number
          created_at: string
          estimated_cost_brl: number
          id: string
          presentation_date: string
          primary_author_name: string
          status: Database["public"]["Enums"]["submission_status"]
          submission_date: string
          target_name: string
          target_type: Database["public"]["Enums"]["submission_target_type"]
          title: string
          tribe_name: string
        }[]
      }
      get_ratification_reminder_targets: {
        Args: { p_document_id: string }
        Returns: {
          chain_id: string
          days_since_chain_opened: number
          email: string
          expected_gate_kind: string
          member_id: string
          name: string
          person_id: string
          target_type: string
          version_label: string
        }[]
      }
      get_recent_events: {
        Args: { p_days_back?: number; p_days_forward?: number }
        Returns: {
          date: string
          duration_actual: number
          duration_minutes: number
          headcount: number
          id: string
          title: string
          tribe_id: number
          tribe_name: string
          type: string
        }[]
      }
      get_recent_showcases_by_member: {
        Args: { p_days?: number; p_member_id: string }
        Returns: {
          event_date: string
          event_id: string
          event_title: string
          registered_at: string
          showcase_id: string
          showcase_title: string
          showcase_type: string
          xp_awarded: number
        }[]
      }
      get_revenue_entries: {
        Args: {
          p_category_name?: string
          p_date_from?: string
          p_date_to?: string
          p_limit?: number
        }
        Returns: {
          amount_brl: number
          category_description: string
          category_name: string
          created_at: string
          created_by_name: string
          date: string
          description: string
          id: string
          notes: string
          value_type: string
        }[]
      }
      get_section_change_history: {
        Args: { p_section_id: string }
        Returns: Json
      }
      get_security_incidents: {
        Args: { p_limit?: number; p_severity?: string; p_status?: string }
        Returns: {
          action: string
          actor_id: string
          audit_id: string
          brief_path: string
          created_at: string
          incident_id: string
          severity: string
          status: string
          summary: string
          target_id: string
          target_type: string
        }[]
      }
      get_selection_committee: { Args: { p_cycle_id: string }; Returns: Json }
      get_selection_cycles: { Args: never; Returns: Json }
      get_selection_dashboard: {
        Args: { p_cycle_code?: string }
        Returns: Json
      }
      get_selection_health: { Args: never; Returns: Json }
      get_selection_pipeline_metrics: {
        Args: { p_chapter?: string; p_cycle_id?: string }
        Returns: Json
      }
      get_selection_rankings: {
        Args: { p_cycle_code?: string; p_track?: string }
        Returns: Json
      }
      get_site_config: { Args: never; Returns: Json }
      get_sustainability_dashboard: {
        Args: { p_cycle?: number }
        Returns: Json
      }
      get_sustainability_projections: {
        Args: { p_months_ahead?: number }
        Returns: Json
      }
      get_tags: {
        Args: { p_domain?: string }
        Returns: {
          board_item_count: number
          color: string
          description: string
          display_order: number
          domain: Database["public"]["Enums"]["tag_domain"]
          event_count: number
          id: string
          label_pt: string
          name: string
          tier: Database["public"]["Enums"]["tag_tier"]
        }[]
      }
      get_trail_courses: {
        Args: never
        Returns: {
          code: string
          credly_badge_name: string
          has_credly: boolean
          is_trail: boolean
          name: string
          sort_order: number
          tier: string
          url: string
        }[]
      }
      get_tribe_attendance_grid: {
        Args: { p_event_type?: string; p_tribe_id: number }
        Returns: Json
      }
      get_tribe_counts: {
        Args: never
        Returns: {
          member_count: number
          tribe_id: number
        }[]
      }
      get_tribe_credly_status: { Args: { p_tribe_id: number }; Returns: Json }
      get_tribe_event_roster: { Args: { p_event_id: string }; Returns: Json }
      get_tribe_events_timeline: {
        Args: {
          p_past_limit?: number
          p_tribe_id: number
          p_upcoming_limit?: number
        }
        Returns: Json
      }
      get_tribe_gamification: { Args: { p_tribe_id: number }; Returns: Json }
      get_tribe_housekeeping: {
        Args: { p_initiative_id?: string; p_legacy_tribe_id?: number }
        Returns: Json
      }
      get_tribe_member_contacts: { Args: { p_tribe_id: number }; Returns: Json }
      get_tribe_members_with_credly: {
        Args: { p_tribe_id: number }
        Returns: Json
      }
      get_tribe_stats: { Args: { p_tribe_id: number }; Returns: Json }
      get_unread_notification_count: { Args: never; Returns: number }
      get_vep_baseline_history: { Args: { p_limit?: number }; Returns: Json }
      get_vep_divergence_report: { Args: never; Returns: Json }
      get_version_diff: {
        Args: {
          p_include_content?: boolean
          p_version_a: string
          p_version_b: string
        }
        Returns: Json
      }
      get_volunteer_agreement_status: { Args: never; Returns: Json }
      get_volunteer_funnel_stats: {
        Args: { p_cycle_id?: string }
        Returns: Json
      }
      get_webinar_lifecycle: { Args: { p_webinar_id: string }; Returns: Json }
      get_weekly_card_digest: { Args: { p_member_id: string }; Returns: Json }
      get_weekly_initiative_digest: {
        Args: { p_initiative_id: string }
        Returns: Json
      }
      get_weekly_member_digest: { Args: { p_member_id: string }; Returns: Json }
      get_weekly_tribe_digest: { Args: { p_tribe_id: number }; Returns: Json }
      get_wiki_page: {
        Args: { p_path: string }
        Returns: {
          authors: string[]
          content: string
          domain: string
          id: string
          ip_track: string
          license: string
          path: string
          source_sha: string
          summary: string
          synced_at: string
          tags: string[]
          title: string
          updated_at: string
        }[]
      }
      give_consent_via_token: {
        Args: { p_consent_type?: string; p_token: string }
        Returns: Json
      }
      import_historical_evaluations: { Args: { p_data: Json }; Returns: Json }
      import_historical_interviews: { Args: { p_data: Json }; Returns: Json }
      import_leader_evaluations: { Args: { p_data: Json }; Returns: Json }
      import_vep_applications: {
        Args: {
          p_cycle_id: string
          p_opportunity_id?: string
          p_role?: string
          p_rows: Json
        }
        Returns: Json
      }
      increment_blog_view: { Args: { p_slug: string }; Returns: undefined }
      increment_publication_view: { Args: { p_id: string }; Returns: undefined }
      invite_alumni_to_re_engage: {
        Args: { p_message?: string; p_pipeline_id: string }
        Returns: Json
      }
      is_eu_resident: { Args: { p_person_id: string }; Returns: boolean }
      is_event_mandatory_for_member: {
        Args: { p_event_id: string; p_member_id: string }
        Returns: boolean
      }
      issue_certificate: { Args: { p_data: Json }; Returns: Json }
      issue_interview_booking_token: {
        Args: { p_application_id: string; p_bypass_gate?: boolean }
        Returns: Json
      }
      join_initiative: {
        Args: {
          p_initiative_id: string
          p_metadata?: Json
          p_motivation?: string
        }
        Returns: string
      }
      knowledge_assets_latest: {
        Args: { p_limit?: number; p_source?: string }
        Returns: {
          asset_id: string
          chunk_count: number
          external_id: string
          language: string
          published_at: string
          source: string
          source_url: string
          summary: string
          tags: string[]
          title: string
        }[]
      }
      knowledge_insights_backlog_candidates: {
        Args: { p_limit?: number; p_status?: string }
        Returns: {
          confidence_score: number
          detected_at: string
          evidence_url: string
          impact_score: number
          insight_id: string
          insight_type: string
          priority_score: number
          status: string
          taxonomy_area: string
          title: string
          urgency_score: number
        }[]
      }
      knowledge_insights_overview: {
        Args: { p_days?: number; p_status?: string }
        Returns: {
          avg_impact: number
          avg_urgency: number
          insight_type: string
          items: number
          max_detected_at: string
          taxonomy_area: string
        }[]
      }
      knowledge_search: {
        Args: {
          p_match_count?: number
          p_query_embedding: string
          p_source?: string
        }
        Returns: {
          asset_id: string
          chunk_id: string
          similarity: number
          snippet: string
          source: string
          source_url: string
          tags: string[]
          title: string
        }[]
      }
      knowledge_search_text: {
        Args: { p_match_count?: number; p_query: string; p_source?: string }
        Returns: {
          asset_id: string
          chunk_id: string
          rank: number
          snippet: string
          source: string
          source_url: string
          tags: string[]
          title: string
        }[]
      }
      link_attachment_to_governance: {
        Args: {
          p_attachment_id: string
          p_parties?: string[]
          p_signed_at?: string
          p_title: string
        }
        Returns: Json
      }
      link_board_to_drive: {
        Args: {
          p_board_id: string
          p_drive_folder_id: string
          p_drive_folder_name?: string
          p_drive_folder_url: string
        }
        Returns: Json
      }
      link_idea_to_series: {
        Args: { p_idea_id: string; p_position?: number; p_series_id: string }
        Returns: Json
      }
      link_initiative_to_drive: {
        Args: {
          p_drive_folder_id: string
          p_drive_folder_name?: string
          p_drive_folder_url: string
          p_initiative_id: string
          p_link_purpose?: string
        }
        Returns: Json
      }
      link_interview_event: {
        Args: { p_application_id: string; p_event_id: string }
        Returns: Json
      }
      link_my_credly_badge: {
        Args: { p_badge_name?: string; p_badge_url: string }
        Returns: Json
      }
      link_partner_to_card: {
        Args: {
          p_board_item_id: string
          p_link_role?: string
          p_notes?: string
          p_partner_entity_id: string
        }
        Returns: Json
      }
      link_webinar_event: {
        Args: { p_event_id?: string; p_webinar_id: string }
        Returns: Json
      }
      list_active_boards: {
        Args: never
        Returns: {
          board_name: string
          board_scope: string
          domain_key: string
          id: string
          item_count: number
          source: string
          tribe_id: number
        }[]
      }
      list_admin_links: {
        Args: never
        Returns: {
          category: string
          created_at: string
          created_by: string | null
          description: string | null
          icon: string | null
          id: number
          is_active: boolean
          sort_order: number | null
          title: string
          updated_at: string
          url: string
        }[]
        SetofOptions: {
          from: "*"
          to: "admin_links"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_ai_calibration_runs: {
        Args: { p_cycle_id?: string; p_limit?: number }
        Returns: Json
      }
      list_ai_processing_log: {
        Args: {
          p_application_id?: string
          p_limit?: number
          p_purpose?: string
          p_status?: string
        }
        Returns: Json
      }
      list_ai_suggestions: {
        Args: {
          p_application_id: string
          p_evaluation_type?: string
          p_only_pending?: boolean
        }
        Returns: Json
      }
      list_anonymization_candidates: {
        Args: { p_years?: number }
        Returns: {
          chapter: string
          email: string
          inactivated_at: string
          inactivity_anchor: string
          last_seen_at: string
          member_id: string
          name: string
          offboarded_at: string
          updated_at: string
          years_inactive: number
        }[]
      }
      list_board_items: {
        Args: { p_board_id: string; p_status?: string }
        Returns: Json[]
      }
      list_card_comments: { Args: { p_board_item_id: string }; Returns: Json }
      list_card_drive_files: {
        Args: { p_board_item_id: string }
        Returns: Json
      }
      list_card_partners: {
        Args: { p_board_item_id: string }
        Returns: {
          link_id: string
          link_notes: string
          link_role: string
          linked_at: string
          linked_by_name: string
          partner_chapter: string
          partner_contact_name: string
          partner_entity_id: string
          partner_entity_type: string
          partner_name: string
          partner_status: string
        }[]
      }
      list_curation_board: { Args: { p_status?: string }; Returns: Json[] }
      list_curation_pending_board_items: { Args: never; Returns: Json[] }
      list_cycles: { Args: never; Returns: Json }
      list_document_comments: {
        Args: {
          p_include_prior_versions?: boolean
          p_include_resolved?: boolean
          p_version_id: string
        }
        Returns: {
          author_id: string
          author_name: string
          author_role: string
          body: string
          clause_anchor: string
          created_at: string
          from_version_id: string
          from_version_label: string
          id: string
          is_inherited: boolean
          parent_id: string
          resolution_note: string
          resolved_at: string
          resolved_by_name: string
          visibility: string
        }[]
      }
      list_document_versions: {
        Args: { p_document_id: string }
        Returns: {
          authored_at: string
          authored_by: string
          authored_by_name: string
          comments_total: number
          comments_unresolved: number
          content_html_length: number
          has_markdown: boolean
          is_current: boolean
          locked_at: string
          locked_by_name: string
          notes: string
          published_at: string
          version_id: string
          version_label: string
          version_number: number
        }[]
      }
      list_drive_discoveries: {
        Args: {
          p_initiative_id?: string
          p_limit?: number
          p_offset?: number
          p_status_filter?: string
        }
        Returns: Json
      }
      list_initiative_boards: {
        Args: { p_initiative_id?: string }
        Returns: Json[]
      }
      list_initiative_deliverables: {
        Args: { p_cycle_code?: string; p_initiative_id: string }
        Returns: {
          artifact_id: string | null
          assigned_member_id: string | null
          created_at: string
          cycle_code: string
          description: string | null
          description_i18n: Json
          due_date: string | null
          id: string
          initiative_id: string | null
          organization_id: string
          status: string
          title: string
          title_i18n: Json
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "tribe_deliverables"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_initiative_engagements: {
        Args: { p_initiative_id: string; p_status_filter?: string }
        Returns: Json
      }
      list_initiative_engagements_by_kind: {
        Args: {
          p_engagement_kind?: string
          p_initiative_kind?: string
          p_limit?: number
          p_status_filter?: string
        }
        Returns: Json
      }
      list_initiative_events: {
        Args: {
          p_date_from?: string
          p_date_to?: string
          p_has_attendance?: boolean
          p_has_minutes?: boolean
          p_has_recording?: boolean
          p_initiative_id?: string
          p_limit?: number
          p_offset?: number
          p_tribe_id?: number
          p_types?: string[]
        }
        Returns: Json
      }
      list_initiative_meeting_artifacts: {
        Args: { p_initiative_id?: string; p_limit?: number }
        Returns: {
          agenda_items: string[] | null
          created_at: string
          created_by: string | null
          cycle_code: string | null
          deliberations: string[] | null
          event_id: string | null
          id: string
          initiative_id: string | null
          is_published: boolean
          meeting_date: string
          organization_id: string
          page_data_snapshot: Json | null
          recording_url: string | null
          title: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "meeting_artifacts"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_initiatives: {
        Args: { p_kind?: string; p_status?: string }
        Returns: Json[]
      }
      list_invitations_for_my_initiatives: {
        Args: { p_initiative_id?: string; p_status_filter?: string }
        Returns: Json
      }
      list_legacy_board_items_for_tribe: {
        Args: { p_current_tribe_id: number }
        Returns: Json[]
      }
      list_meeting_action_items: {
        Args: {
          p_assignee_id?: string
          p_event_id?: string
          p_kind?: string
          p_status?: string
          p_unresolved_only?: boolean
        }
        Returns: Json
      }
      list_meeting_artifacts: {
        Args: { p_limit?: number; p_tribe_id?: number }
        Returns: {
          agenda_items: string[] | null
          created_at: string
          created_by: string | null
          cycle_code: string | null
          deliberations: string[] | null
          event_id: string | null
          id: string
          initiative_id: string | null
          is_published: boolean
          meeting_date: string
          organization_id: string
          page_data_snapshot: Json | null
          recording_url: string | null
          title: string
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "meeting_artifacts"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_meetings_with_notes: {
        Args: {
          p_include_empty?: boolean
          p_limit?: number
          p_offset?: number
          p_search?: string
          p_tribe_id?: number
          p_type?: string
        }
        Returns: Json
      }
      list_my_ai_validations: {
        Args: { p_application_id: string }
        Returns: Json
      }
      list_my_document_drafts: {
        Args: never
        Returns: {
          authored_at: string
          doc_type: string
          document_id: string
          document_title: string
          notes: string
          updated_at: string
          version_id: string
          version_label: string
          version_number: number
        }[]
      }
      list_offboarding_records: {
        Args: {
          p_limit?: number
          p_reason_category?: string
          p_since?: string
          p_until?: string
        }
        Returns: {
          cycle_code_at_offboard: string
          has_full_interview: boolean
          member_chapter: string
          member_id: string
          member_name: string
          member_status: string
          offboarded_at: string
          offboarded_by: string
          reason_category_code: string
          reason_category_label_pt: string
          record_id: string
          return_interest: boolean
          tribe_id_at_offboard: number
        }[]
      }
      list_open_initiatives: { Args: never; Returns: Json }
      list_orphan_card_assignments: {
        Args: { p_chapter?: string; p_limit?: number; p_tribe_id?: number }
        Returns: Json
      }
      list_orphan_interview_events: {
        Args: never
        Returns: {
          calendar_event_id: string
          duration_minutes: number
          event_date: string
          event_id: string
          source: string
          status: string
          suggested_applications: Json
          time_start: string
          title: string
        }[]
      }
      list_partner_cards: {
        Args: { p_partner_entity_id: string }
        Returns: {
          board_id: string
          board_item_assignee_name: string
          board_item_due_date: string
          board_item_id: string
          board_item_status: string
          board_item_title: string
          board_name: string
          link_id: string
          link_notes: string
          link_role: string
          linked_at: string
          linked_by_name: string
          partner_entity_id: string
          partner_name: string
        }[]
      }
      list_pending_curation: { Args: { p_table?: string }; Returns: Json }
      list_project_boards: { Args: { p_tribe_id?: number }; Returns: Json[] }
      list_radar_global: {
        Args: { p_publications_limit?: number; p_webinars_limit?: number }
        Returns: Json
      }
      list_re_engagement_pipeline: {
        Args: { p_cycle_code?: string; p_state?: string }
        Returns: Json
      }
      list_taxonomy_tags: {
        Args: never
        Returns: {
          category: string
          id: number
          is_active: boolean
          kpi_ref: string | null
          label_en: string
          label_es: string
          label_pt: string
          tag_key: string
        }[]
        SetofOptions: {
          from: "*"
          to: "taxonomy_tags"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_tribe_deliverables: {
        Args: { p_cycle_code?: string; p_tribe_id: number }
        Returns: {
          artifact_id: string | null
          assigned_member_id: string | null
          created_at: string
          cycle_code: string
          description: string | null
          description_i18n: Json
          due_date: string | null
          id: string
          initiative_id: string | null
          organization_id: string
          status: string
          title: string
          title_i18n: Json
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "tribe_deliverables"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      list_validations_by_validator: {
        Args: { p_cycle_id?: string; p_limit?: number; p_validator_id: string }
        Returns: Json
      }
      list_visitor_leads: {
        Args: { p_chapter?: string; p_limit?: number; p_status?: string }
        Returns: Json
      }
      list_webinar_proposals: {
        Args: { p_status_filter?: string }
        Returns: Json
      }
      list_webinars_v2: {
        Args: { p_chapter?: string; p_status?: string; p_tribe_id?: number }
        Returns: Json
      }
      lock_document_version: {
        Args: { p_gates: Json; p_version_id: string }
        Returns: Json
      }
      log_cron_run_complete: {
        Args: {
          p_errors?: Json
          p_metrics?: Json
          p_run_id: string
          p_status: string
        }
        Returns: undefined
      }
      log_cron_run_start: {
        Args: {
          p_metrics?: Json
          p_scheduled_for: string
          p_worker_name: string
        }
        Returns: string
      }
      log_mcp_usage: {
        Args: {
          p_auth_user_id: string
          p_error_message?: string
          p_execution_ms?: number
          p_member_id: string
          p_response_summary?: Json
          p_result_kind?: string
          p_success?: boolean
          p_tool_name: string
        }
        Returns: undefined
      }
      log_pii_access: {
        Args: {
          p_context: string
          p_fields: string[]
          p_reason?: string
          p_target_member_id: string
        }
        Returns: undefined
      }
      log_pii_access_batch: {
        Args: {
          p_context: string
          p_fields: string[]
          p_reason?: string
          p_target_member_ids: string[]
        }
        Returns: number
      }
      log_security_incident: {
        Args: {
          p_brief_path?: string
          p_category: string
          p_event: string
          p_extra?: Json
          p_incident_id?: string
          p_severity?: string
          p_status?: string
          p_summary?: string
          p_target_id?: string
          p_target_type?: string
        }
        Returns: Json
      }
      log_topic_view: {
        Args: { p_ip?: unknown; p_token: string; p_ua?: string }
        Returns: Json
      }
      manage_action_items: {
        Args: { p_event_id: string; p_items: Json }
        Returns: Json
      }
      manage_initiative_engagement: {
        Args: {
          p_action: string
          p_initiative_id: string
          p_kind: string
          p_person_id: string
          p_role: string
        }
        Returns: Json
      }
      manage_selection_committee: {
        Args: {
          p_action: string
          p_cycle_id: string
          p_member_id: string
          p_role?: string
        }
        Returns: Json
      }
      mark_all_notifications_read: { Args: never; Returns: Json }
      mark_interview_status: {
        Args: { p_interview_id: string; p_notes?: string; p_status: string }
        Returns: Json
      }
      mark_member_excused: {
        Args: {
          p_event_id: string
          p_excused?: boolean
          p_member_id: string
          p_reason?: string
        }
        Returns: Json
      }
      mark_member_present: {
        Args: { p_event_id: string; p_member_id: string; p_present: boolean }
        Returns: Json
      }
      mark_my_data_reviewed: { Args: never; Returns: Json }
      mark_notification_read: {
        Args: { p_notification_id: string }
        Returns: Json
      }
      mark_vep_reconciled: {
        Args: { p_application_id: string; p_note?: string }
        Returns: Json
      }
      meeting_close: {
        Args: {
          p_event_id: string
          p_suggested_champion_ids?: string[]
          p_summary?: string
        }
        Returns: Json
      }
      member_add_alternate_email: {
        Args: { p_email: string; p_kind: string; p_member_id: string }
        Returns: string
      }
      member_list_emails: {
        Args: { p_member_id: string }
        Returns: {
          added_at: string
          email: string
          id: string
          is_primary: boolean
          kind: string
          member_id: string
          organization_id: string
        }[]
      }
      member_remove_alternate_email: {
        Args: { p_email: string; p_member_id: string }
        Returns: boolean
      }
      member_resolve_email: { Args: { p_email: string }; Returns: string }
      member_self_update: {
        Args: {
          p_credly_url?: string
          p_linkedin_url?: string
          p_phone?: string
          p_pmi_id?: string
          p_share_whatsapp?: boolean
        }
        Returns: Json
      }
      member_set_primary_email: {
        Args: { p_email: string; p_member_id: string }
        Returns: boolean
      }
      member_update_alternate_email_kind: {
        Args: { p_email: string; p_member_id: string; p_new_kind: string }
        Returns: boolean
      }
      mirror_sibling_interview: {
        Args: { p_application_id: string }
        Returns: Json
      }
      move_board_item: {
        Args: {
          p_item_id: string
          p_new_position?: number
          p_new_status: string
          p_reason?: string
        }
        Returns: undefined
      }
      move_item_to_board: {
        Args: { p_item_id: string; p_target_board_id: string }
        Returns: undefined
      }
      notify_privacy_policy_change: {
        Args: { p_version_id: string }
        Returns: Json
      }
      offboard_member: {
        Args: {
          p_effective_date?: string
          p_member_id: string
          p_new_status: string
          p_reason: string
        }
        Returns: Json
      }
      opt_out_all_pillars: { Args: { p_token: string }; Returns: Json }
      parse_vep_chapters: { Args: { p_membership: string }; Returns: string[] }
      platform_activity_summary: { Args: never; Returns: Json }
      preview_gate_eligibles: {
        Args: { p_doc_type: string; p_submitter_id: string }
        Returns: Json
      }
      process_email_webhook: {
        Args: {
          p_event_type: string
          p_resend_id: string
          p_update_fields?: Json
        }
        Returns: undefined
      }
      process_interview_reminders_1h: { Args: never; Returns: Json }
      process_pending_email_queue: { Args: never; Returns: Json }
      process_pending_reschedule_nudges: { Args: never; Returns: Json }
      promote_lead_to_application: {
        Args: { p_cycle_id: string; p_lead_id: string; p_pmi_id?: string }
        Returns: Json
      }
      promote_to_leader_track: {
        Args: { p_application_id: string; p_create_leader_app?: boolean }
        Returns: Json
      }
      propose_manual_version: {
        Args: { p_notes?: string; p_version_label: string }
        Returns: Json
      }
      propose_publication_idea: {
        Args: {
          p_author_ids?: string[]
          p_initiative_id?: string
          p_metadata?: Json
          p_proposed_channels?: string[]
          p_series_id?: string
          p_series_position?: number
          p_source_id?: string
          p_source_type?: string
          p_summary?: string
          p_target_languages?: string[]
          p_themes?: string[]
          p_title: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      publish_board_item_from_curation: {
        Args: { p_item_id: string }
        Returns: string
      }
      publish_comms_metrics_batch: {
        Args: { p_metric_date?: string; p_source?: string }
        Returns: {
          batch_id: string
          published_at: string
          published_rows: number
          source: string
          target_date: string
        }[]
      }
      purge_expired_logs: {
        Args: { p_dry_run?: boolean; p_limit?: number }
        Returns: {
          oldest_row_kept: string
          purge_mode: string
          rows_affected: number
          table_name: string
        }[]
      }
      purge_stale_digest_notifications_cron: { Args: never; Returns: Json }
      recalculate_cycle_rankings: {
        Args: { p_cycle_id: string; p_reason?: string }
        Returns: Json
      }
      recirculate_governance_doc: {
        Args: {
          p_chain_id: string
          p_dry_run?: boolean
          p_recipient_emails?: string[]
        }
        Returns: Json
      }
      recompute_all_active_pert_cutoffs: { Args: never; Returns: Json }
      record_ai_validation: {
        Args: {
          p_ai_model?: string
          p_ai_purpose: string
          p_ai_score?: number
          p_ai_verdict?: string
          p_application_id: string
          p_comment?: string
          p_override_score?: number
          p_validation_action: string
        }
        Returns: Json
      }
      record_drive_discovery: {
        Args: {
          p_drive_file_id: string
          p_drive_file_url: string
          p_drive_modified_at?: string
          p_filename: string
          p_initiative_drive_link_id: string
          p_mime_type?: string
          p_size_bytes?: number
        }
        Returns: Json
      }
      record_member_activity: { Args: { p_page?: string }; Returns: undefined }
      record_offboarding_interview: {
        Args: {
          p_attachment_urls?: string[]
          p_exit_interview_full_text?: string
          p_exit_interview_source?: string
          p_lessons_learned?: string
          p_member_id: string
          p_reason_category_code?: string
          p_recommendation_for_future?: string
          p_referred_by_tribe_leader?: boolean
          p_return_interest?: boolean
          p_return_window_suggestion?: string
        }
        Returns: Json
      }
      refresh_cycle_tribe_dim: { Args: never; Returns: undefined }
      refresh_preview_gate_eligibles_cache_all: { Args: never; Returns: Json }
      register_attendance_batch: {
        Args: {
          p_event_id: string
          p_member_ids: string[]
          p_registered_by?: string
        }
        Returns: number
      }
      register_card_drive_file: {
        Args: {
          p_board_item_id: string
          p_drive_file_id: string
          p_drive_file_url: string
          p_filename: string
          p_mime_type?: string
          p_size_bytes?: number
          p_uploaded_via?: string
        }
        Returns: Json
      }
      register_decision: {
        Args: {
          p_description?: string
          p_event_id: string
          p_related_card_ids?: string[]
          p_title: string
        }
        Returns: Json
      }
      register_event_showcase: {
        Args: {
          p_duration_min?: number
          p_event_id: string
          p_member_id: string
          p_notes?: string
          p_showcase_type: string
          p_title?: string
        }
        Returns: Json
      }
      register_own_presence: { Args: { p_event_id: string }; Returns: Json }
      register_video_screening: {
        Args: {
          p_drive_file_id?: string
          p_drive_file_name?: string
          p_drive_folder_id?: string
          p_pillar: string
          p_question_index: number
          p_question_text: string
          p_storage_provider: string
          p_token: string
          p_youtube_url?: string
        }
        Returns: Json
      }
      remove_event_showcase: { Args: { p_showcase_id: string }; Returns: Json }
      remove_publication_submission_author: {
        Args: { p_member_id: string; p_submission_id: string }
        Returns: undefined
      }
      remove_secondary_email: { Args: { p_email: string }; Returns: Json }
      request_application_enrichment: {
        Args: { p_field_updates: Json; p_token: string }
        Returns: Json
      }
      request_interview_reschedule: {
        Args: { p_application_id: string; p_reason: string }
        Returns: Json
      }
      request_secondary_email_verification: {
        Args: { p_email: string }
        Returns: Json
      }
      request_to_join_initiative: {
        Args: { p_initiative_id: string; p_message: string }
        Returns: Json
      }
      resolve_action_item: {
        Args: {
          p_action_item_id: string
          p_carry_to_event_id?: string
          p_resolution_note?: string
        }
        Returns: Json
      }
      resolve_default_gates: { Args: { p_doc_type: string }; Returns: Json }
      resolve_document_comment: {
        Args: { p_comment_id: string; p_resolution_note?: string }
        Returns: Json
      }
      resolve_initiative_id: { Args: { p_tribe_id: number }; Returns: string }
      resolve_tribe_id: { Args: { p_initiative_id: string }; Returns: number }
      resolve_whatsapp_link: { Args: { p_member_id: string }; Returns: Json }
      respond_re_engagement: {
        Args: { p_note?: string; p_pipeline_id: string; p_response: string }
        Returns: Json
      }
      respond_to_initiative_invitation: {
        Args: { p_invitation_id: string; p_note?: string; p_response: string }
        Returns: Json
      }
      retry_pending_ai_analyses: { Args: never; Returns: Json }
      retry_pending_ai_triages: { Args: never; Returns: Json }
      revert_interview_optout: { Args: { p_token: string }; Returns: Json }
      review_change_request: {
        Args: { p_action: string; p_cr_id: string; p_notes: string }
        Returns: Json
      }
      review_initiative_request: {
        Args: { p_decision: string; p_invitation_id: string; p_note?: string }
        Returns: Json
      }
      review_webinar_proposal: {
        Args: {
          p_decision: string
          p_proposal_id: string
          p_rejection_reason?: string
          p_review_notes?: string
        }
        Returns: Json
      }
      revoke_champion: {
        Args: { p_champion_id: string; p_reason: string }
        Returns: Json
      }
      revoke_consent_via_token: {
        Args: { p_consent_type?: string; p_token: string }
        Returns: Json
      }
      rls_can: { Args: { p_action: string }; Returns: boolean }
      rls_can_for_initiative: {
        Args: { p_action: string; p_initiative_id: string }
        Returns: boolean
      }
      rls_can_for_tribe: {
        Args: { p_action: string; p_tribe_id: number }
        Returns: boolean
      }
      rls_is_member: { Args: never; Returns: boolean }
      rls_is_superadmin: { Args: never; Returns: boolean }
      save_presentation_snapshot: {
        Args: {
          p_agenda_items?: string[]
          p_deliberations?: string[]
          p_event_id?: string
          p_is_published?: boolean
          p_meeting_date: string
          p_recording_url?: string
          p_snapshot?: Json
          p_title: string
          p_tribe_id?: number
        }
        Returns: string
      }
      schedule_interview: {
        Args: {
          p_application_id: string
          p_bypass_gate?: boolean
          p_calendar_event_id?: string
          p_duration_minutes?: number
          p_interviewer_ids: string[]
          p_scheduled_at: string
        }
        Returns: Json
      }
      search_board_items: {
        Args: { p_query: string; p_tribe_id?: number }
        Returns: Json[]
      }
      search_hub_resources: {
        Args: { p_asset_type?: string; p_limit?: number; p_query: string }
        Returns: {
          asset_type: string
          created_at: string
          description: string
          id: string
          source: string
          tags: string[]
          title: string
          tribe_id: number
          url: string
        }[]
      }
      search_initiative_board_items: {
        Args: { p_initiative_id?: string; p_query: string }
        Returns: Json[]
      }
      search_knowledge: {
        Args: { search_term: string }
        Returns: {
          artifact_id: string
          asset_id: string
          chunk_id: string
          content_snippet: string
          theme_title: string
          tribe_name: string
        }[]
      }
      search_partner_cards: {
        Args: {
          p_card_status?: string
          p_chapter?: string
          p_limit?: number
          p_link_role?: string
        }
        Returns: {
          board_id: string
          board_item_assignee_name: string
          board_item_due_date: string
          board_item_id: string
          board_item_status: string
          board_item_title: string
          board_name: string
          link_id: string
          link_notes: string
          link_role: string
          linked_at: string
          linked_by_name: string
          partner_chapter: string
          partner_entity_id: string
          partner_name: string
          partner_status: string
        }[]
      }
      search_wiki_pages: {
        Args: {
          p_domain?: string
          p_limit?: number
          p_query: string
          p_tag?: string
        }
        Returns: {
          domain: string
          headline: string
          id: string
          ip_track: string
          license: string
          path: string
          rank: number
          summary: string
          tags: string[]
          title: string
        }[]
      }
      seed_member_engagement_by_role: {
        Args: {
          p_initiative_id?: string
          p_person_id: string
          p_template_slug: string
        }
        Returns: Json
      }
      seed_pre_onboarding_steps: {
        Args: { p_application_id: string; p_member_id?: string }
        Returns: Json
      }
      select_tribe: { Args: { p_tribe_id: number }; Returns: Json }
      send_attendance_reminders: { Args: never; Returns: Json }
      send_attendance_reminders_cron: { Args: never; Returns: Json }
      set_event_audience: {
        Args: { p_event_id: string; p_rules: Json }
        Returns: undefined
      }
      set_event_invited_members: {
        Args: { p_event_id: string; p_members: Json }
        Returns: undefined
      }
      set_my_gamification_visibility: {
        Args: { p_opt_out: boolean }
        Returns: Json
      }
      set_my_muted_notification_types: {
        Args: { p_muted_types: string[] }
        Returns: Json
      }
      set_my_notification_prefs: {
        Args: {
          p_notify_delivery_mode_pref?: string
          p_notify_weekly_digest?: boolean
        }
        Returns: Json
      }
      set_progress: {
        Args: { p_code: string; p_email: string; p_status: string }
        Returns: undefined
      }
      set_site_config:
        | { Args: { p_key: string; p_value: Json }; Returns: undefined }
        | { Args: { p_key: string; p_value: string }; Returns: undefined }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      sign_ip_ratification: {
        Args: {
          p_chain_id: string
          p_comment_body?: string
          p_gate_kind: string
          p_sections_verified?: Json
          p_signoff_type?: string
          p_ue_consent_49_1_a?: boolean
        }
        Returns: Json
      }
      sign_volunteer_agreement: {
        Args: {
          p_language?: string
          p_signed_ip?: string
          p_signed_user_agent?: string
        }
        Returns: Json
      }
      stage_alumni_for_re_engagement: {
        Args: { p_cycle_code: string; p_member_id: string; p_source?: string }
        Returns: Json
      }
      submit_change_request: {
        Args: {
          p_cr_type: string
          p_description: string
          p_gc_references?: string[]
          p_impact_description?: string
          p_impact_level?: string
          p_justification?: string
          p_manual_section_ids?: string[]
          p_title: string
        }
        Returns: Json
      }
      submit_chapter_need: {
        Args: { p_category: string; p_description?: string; p_title: string }
        Returns: Json
      }
      submit_cpmai_mock_score: {
        Args: {
          p_correct_answers?: number
          p_course_id: string
          p_mock_source?: string
          p_notes?: string
          p_score_pct: number
          p_total_questions?: number
        }
        Returns: Json
      }
      submit_curation_review: {
        Args: {
          p_criteria_scores?: Json
          p_decision: string
          p_feedback_notes?: string
          p_item_id: string
        }
        Returns: string
      }
      submit_evaluation: {
        Args: {
          p_ai_suggestion_id?: string
          p_application_id: string
          p_criterion_notes?: Json
          p_evaluation_type: string
          p_notes?: string
          p_scores: Json
        }
        Returns: Json
      }
      submit_for_curation: { Args: { p_item_id: string }; Returns: undefined }
      submit_interview_scores: {
        Args: {
          p_criterion_notes?: Json
          p_interview_id: string
          p_notes?: string
          p_scores: Json
          p_theme?: string
        }
        Returns: Json
      }
      suggest_tags: {
        Args: { p_cycle_code?: string; p_title: string; p_type?: string }
        Returns: string[]
      }
      sync_attendance_points: { Args: never; Returns: Json }
      sync_calendar_booking_to_interview: {
        Args: { p_payload: Json }
        Returns: Json
      }
      title_case: { Args: { input: string }; Returns: string }
      toggle_blog_like: { Args: { p_post_id: string }; Returns: Json }
      tribe_impact_ranking: {
        Args: never
        Returns: {
          avg_attendance: number
          total_events: number
          total_hours: number
          tribe_id: number
          tribe_name: string
        }[]
      }
      trigger_ai_calibration_run: { Args: never; Returns: Json }
      trigger_backup: { Args: never; Returns: Json }
      try_auto_link_ghost: {
        Args: never
        Returns: {
          address: string | null
          anonymized_at: string | null
          anonymized_by: string | null
          auth_id: string | null
          birth_date: string | null
          chapter: string
          city: string | null
          country: string | null
          cpmai_certified: boolean | null
          cpmai_certified_at: string | null
          created_at: string | null
          credly_badges: Json | null
          credly_url: string | null
          credly_verified_at: string | null
          current_cycle_active: boolean | null
          cycles: string[] | null
          data_last_reviewed_at: string | null
          designations: string[] | null
          email: string
          gamification_opt_out: boolean
          id: string
          inactivated_at: string | null
          inactivation_reason: string | null
          initiative_id: string | null
          is_active: boolean | null
          is_superadmin: boolean | null
          last_active_pages: string[] | null
          last_seen_at: string | null
          linkedin_url: string | null
          member_status: string | null
          name: string
          notify_delivery_mode_pref: string
          notify_weekly_digest: boolean
          offboarded_at: string | null
          offboarded_by: string | null
          onboarding_dismissed_at: string | null
          operational_role: string | null
          organization_id: string
          person_id: string | null
          phone: string | null
          phone_encrypted: string | null
          photo_url: string | null
          pmi_id: string | null
          pmi_id_encrypted: string | null
          pmi_id_verified: boolean | null
          privacy_consent_accepted_at: string | null
          privacy_consent_version: string | null
          profile_completed_at: string | null
          secondary_auth_ids: string[] | null
          secondary_emails: string[] | null
          share_address: boolean | null
          share_birth_date: boolean | null
          share_whatsapp: boolean
          signature_url: string | null
          state: string | null
          status_change_reason: string | null
          status_changed_at: string | null
          total_sessions: number | null
          tribe_id: number | null
          updated_at: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "members"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      unassign_member_from_item: {
        Args: { p_item_id: string; p_member_id: string; p_role: string }
        Returns: undefined
      }
      uncancel_event_occurrence: { Args: { p_event_id: string }; Returns: Json }
      unlink_board_from_drive: { Args: { p_link_id: string }; Returns: Json }
      unlink_initiative_from_drive: {
        Args: { p_link_id: string }
        Returns: Json
      }
      unlink_partner_from_card: {
        Args: { p_board_item_id: string; p_partner_entity_id: string }
        Returns: Json
      }
      update_application_contact: {
        Args: {
          p_application_id: string
          p_linkedin_url?: string
          p_phone?: string
        }
        Returns: Json
      }
      update_application_profile_via_token: {
        Args: {
          p_credly_url?: string
          p_linkedin_url?: string
          p_phone?: string
          p_token: string
        }
        Returns: Json
      }
      update_board_item: {
        Args: { p_fields: Json; p_item_id: string }
        Returns: undefined
      }
      update_card_comment: {
        Args: { p_comment_id: string; p_new_body: string }
        Returns: Json
      }
      update_card_during_meeting: {
        Args: {
          p_card_id: string
          p_event_id: string
          p_fields?: Json
          p_new_status?: string
          p_note?: string
        }
        Returns: Json
      }
      update_card_forecast: {
        Args: {
          p_board_item_id: string
          p_justification: string
          p_new_forecast: string
        }
        Returns: undefined
      }
      update_certificate: {
        Args: { p_cert_id: string; p_updates: Json }
        Returns: Json
      }
      update_checklist_item: {
        Args: {
          p_checklist_item_id: string
          p_position?: number
          p_target_date?: string
          p_text?: string
        }
        Returns: undefined
      }
      update_cpmai_progress: {
        Args: { p_module_id: string; p_status: string }
        Returns: Json
      }
      update_event: {
        Args: {
          p_audience_level?: string
          p_date?: string
          p_duration_minutes?: number
          p_event_id: string
          p_external_attendees?: string[]
          p_is_recorded?: boolean
          p_meeting_link?: string
          p_nature?: string
          p_notes?: string
          p_recording_url?: string
          p_time_start?: string
          p_title?: string
          p_type?: string
          p_youtube_url?: string
        }
        Returns: Json
      }
      update_event_duration: {
        Args: {
          p_duration_actual: number
          p_event_id: string
          p_updated_by?: string
        }
        Returns: boolean
      }
      update_event_instance: {
        Args: {
          p_agenda_text?: string
          p_event_id: string
          p_meeting_link?: string
          p_new_date?: string
          p_new_duration_minutes?: number
          p_new_time_start?: string
          p_notes?: string
        }
        Returns: Json
      }
      update_future_events_in_group: {
        Args: {
          p_duration_minutes?: number
          p_event_id: string
          p_meeting_link?: string
          p_nature?: string
          p_new_time_start?: string
          p_notes?: string
          p_type?: string
          p_visibility?: string
        }
        Returns: Json
      }
      update_governance_document_status: {
        Args: { p_doc_id: string; p_new_status: string }
        Returns: Json
      }
      update_initiative: {
        Args: {
          p_description?: string
          p_initiative_id: string
          p_metadata?: Json
          p_status?: string
          p_title?: string
        }
        Returns: Json
      }
      update_kpi_target: {
        Args: {
          p_current_value: number
          p_kpi_id: string
          p_notes: string
          p_target_value: number
        }
        Returns: undefined
      }
      update_my_application: { Args: { p_fields: Json }; Returns: Json }
      update_my_profile: { Args: { p_fields: Json }; Returns: Json }
      update_notification_preferences: {
        Args: { p_prefs: Json }
        Returns: Json
      }
      update_onboarding_step: {
        Args: {
          p_application_id: string
          p_evidence_url?: string
          p_status?: string
          p_step_key: string
        }
        Returns: Json
      }
      update_organization: {
        Args: {
          p_country?: string
          p_description?: string
          p_federated_chapters?: string[]
          p_host_chapter?: string
          p_logo_url?: string
          p_name?: string
          p_primary_language?: string
          p_website_url?: string
        }
        Returns: Json
      }
      update_pilot: {
        Args: {
          p_board_id?: string
          p_completed_at?: string
          p_hypothesis?: string
          p_id: string
          p_lessons_learned?: Json
          p_problem_statement?: string
          p_scope?: string
          p_started_at?: string
          p_status?: string
          p_success_metrics?: Json
          p_team_member_ids?: string[]
          p_title?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      update_pmi_onboarding_step: {
        Args: {
          p_evidence_url?: string
          p_status?: string
          p_step_key: string
          p_token: string
        }
        Returns: Json
      }
      update_publication_submission: {
        Args: {
          p_abstract?: string
          p_acceptance_date?: string
          p_actual_cost_brl?: number
          p_board_item_id?: string
          p_cost_paid_by?: string
          p_doi_or_url?: string
          p_estimated_cost_brl?: number
          p_id: string
          p_presentation_date?: string
          p_review_deadline?: string
          p_reviewer_feedback?: string
          p_submission_date?: string
          p_target_name?: string
          p_target_url?: string
          p_title?: string
        }
        Returns: undefined
      }
      update_publication_submission_status: {
        Args: {
          p_new_status: Database["public"]["Enums"]["submission_status"]
          p_notes?: string
          p_submission_id: string
        }
        Returns: undefined
      }
      update_sustainability_kpi: {
        Args: {
          p_current_value: number
          p_id: string
          p_notes: string
          p_target_value: number
        }
        Returns: undefined
      }
      update_webinar_comms_assets: {
        Args: {
          p_briefing_doc_url?: string
          p_mark_kickoff?: boolean
          p_promo_kit_url?: string
          p_sympla_event_url?: string
          p_webinar_id: string
        }
        Returns: Json
      }
      update_webinar_proposal: {
        Args: {
          p_format_type?: string
          p_notes?: string
          p_proposal_id: string
          p_proposed_by_tribe_id?: number
          p_proposed_speakers?: string[]
          p_proposed_title?: string
          p_quadrant_anchor?: number
          p_series_id?: string
          p_themes?: string[]
        }
        Returns: Json
      }
      upload_my_resume: {
        Args: { p_file_type?: string; p_url: string }
        Returns: Json
      }
      upsert_board_item: {
        Args: {
          p_assignee_id?: string
          p_attachments?: Json
          p_board_id?: string
          p_checklist?: Json
          p_description?: string
          p_due_date?: string
          p_item_id?: string
          p_labels?: Json
          p_status?: string
          p_tags?: string[]
          p_title?: string
        }
        Returns: string
      }
      upsert_document_version: {
        Args: {
          p_content_html: string
          p_content_markdown?: string
          p_document_id: string
          p_notes?: string
          p_version_id?: string
          p_version_label?: string
        }
        Returns: Json
      }
      upsert_event_agenda: {
        Args: { p_event_id: string; p_text?: string; p_url?: string }
        Returns: Json
      }
      upsert_event_minutes: {
        Args: { p_event_id: string; p_text?: string; p_url?: string }
        Returns: Json
      }
      upsert_my_quick_start_step: {
        Args: { p_done?: boolean; p_step_idx: number }
        Returns: Json
      }
      upsert_publication_submission_event: {
        Args: {
          p_board_item_id: string
          p_channel?: string
          p_external_link?: string
          p_notes?: string
          p_outcome?: string
          p_published_at?: string
          p_submitted_at?: string
        }
        Returns: {
          board_item_id: string
          channel: string
          created_at: string
          external_link: string | null
          id: number
          notes: string | null
          outcome: string
          published_at: string | null
          submitted_at: string | null
          updated_at: string
          updated_by: string
        }
        SetofOptions: {
          from: "*"
          to: "publication_submission_events"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_tribe_deliverable: {
        Args: {
          p_artifact_id?: string
          p_assigned_member_id?: string
          p_cycle_code?: string
          p_description?: string
          p_due_date?: string
          p_id?: string
          p_status?: string
          p_title?: string
          p_tribe_id?: number
        }
        Returns: Json
      }
      upsert_webinar: {
        Args: {
          p_board_item_id?: string
          p_chapter_code?: string
          p_co_manager_ids?: string[]
          p_description?: string
          p_duration_min?: number
          p_id?: string
          p_meeting_link?: string
          p_notes?: string
          p_organizer_id?: string
          p_scheduled_at?: string
          p_status?: string
          p_title?: string
          p_tribe_id?: number
          p_youtube_url?: string
        }
        Returns: Json
      }
      v4_expire_engagements: { Args: never; Returns: Json }
      v4_expire_engagements_shadow: { Args: never; Returns: Json }
      v4_notify_expiring_engagements: { Args: never; Returns: Json }
      validate_initiative_metadata: {
        Args: { p_kind: string; p_metadata: Json }
        Returns: boolean
      }
      validate_interview_booking_token: {
        Args: { p_token: string }
        Returns: Json
      }
      validate_privacy_policy_consistency: { Args: never; Returns: Json }
      validate_status_transition: {
        Args: { p_from: string; p_to: string }
        Returns: undefined
      }
      verify_certificate: { Args: { p_code: string }; Returns: Json }
      volunteer_funnel_summary: {
        Args: { p_cycle_code?: string }
        Returns: Json
      }
      webinars_pending_comms: { Args: never; Returns: Json }
      why_denied: {
        Args: {
          p_action: string
          p_person_id: string
          p_resource_id?: string
          p_resource_type?: string
        }
        Returns: Json
      }
      wiki_health_report: {
        Args: never
        Returns: {
          check_type: string
          detail: string
          path: string
          severity: string
          title: string
        }[]
      }
      withdraw_from_initiative: {
        Args: { p_initiative_id: string; p_reason: string }
        Returns: Json
      }
    }
    Enums: {
      re_engagement_state:
        | "staged"
        | "invited"
        | "declined"
        | "accepted"
        | "cancelled"
      submission_status:
        | "draft"
        | "submitted"
        | "under_review"
        | "revision_requested"
        | "accepted"
        | "rejected"
        | "published"
        | "presented"
      submission_target_type:
        | "pmi_global_conference"
        | "pmi_chapter_event"
        | "academic_journal"
        | "academic_conference"
        | "webinar"
        | "blog_post"
        | "other"
        | "linkedin_newsletter"
      tag_domain: "event" | "board_item" | "all"
      tag_tier: "system" | "administrative" | "semantic"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      re_engagement_state: [
        "staged",
        "invited",
        "declined",
        "accepted",
        "cancelled",
      ],
      submission_status: [
        "draft",
        "submitted",
        "under_review",
        "revision_requested",
        "accepted",
        "rejected",
        "published",
        "presented",
      ],
      submission_target_type: [
        "pmi_global_conference",
        "pmi_chapter_event",
        "academic_journal",
        "academic_conference",
        "webinar",
        "blog_post",
        "other",
        "linkedin_newsletter",
      ],
      tag_domain: ["event", "board_item", "all"],
      tag_tier: ["system", "administrative", "semantic"],
    },
  },
} as const
