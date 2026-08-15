\restrict dbmate

-- Dumped from database version 16.15 (Debian 16.15-1.pgdg12+2)
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: budget_policy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.budget_policy (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    monthly_budget_usd numeric,
    daily_budget_usd numeric,
    warning_threshold numeric,
    hard_stop_threshold numeric,
    cheap_model_policy text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: evaluation_cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evaluation_cases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category text NOT NULL,
    question text NOT NULL,
    expected_behavior text,
    expected_language text,
    severity text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: interaction_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.interaction_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id text,
    platform_user_id text NOT NULL,
    platform text NOT NULL,
    user_query text,
    agent_response text,
    routed_model text,
    input_tokens integer,
    output_tokens integer,
    cached_input_tokens integer,
    cost_usd numeric,
    feedback_score smallint,
    needs_review boolean DEFAULT false NOT NULL,
    cache_hit boolean DEFAULT false NOT NULL,
    intent text,
    security_classification text,
    sensitive_data_flagged boolean DEFAULT false NOT NULL,
    sensitive_data_category text,
    prompt_version_id uuid,
    retrieved_kb_ids jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    security_signal text,
    security_signal_reasoning text,
    language text,
    latency_ms integer,
    platform_response_message_id text,
    CONSTRAINT interaction_logs_feedback_score_check CHECK ((feedback_score = ANY (ARRAY[0, 1]))),
    CONSTRAINT interaction_logs_platform_check CHECK ((platform = ANY (ARRAY['telegram'::text, 'whatsapp'::text]))),
    CONSTRAINT interaction_logs_security_classification_check CHECK ((security_classification = ANY (ARRAY['PUBLIC'::text, 'INTERNAL'::text, 'SENSITIVE'::text, 'CLASSIFIED'::text]))),
    CONSTRAINT interaction_logs_security_signal_check CHECK ((security_signal = ANY (ARRAY['PUBLIC'::text, 'INTERNAL'::text, 'SENSITIVE'::text, 'CLASSIFIED'::text])))
);


--
-- Name: knowledge_base; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.knowledge_base (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category text NOT NULL,
    title text NOT NULL,
    url text,
    summary_he text,
    summary_en text,
    source_type text,
    trust_level text,
    embedding public.vector(1536),
    status text DEFAULT 'draft'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: message_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    template_name text NOT NULL,
    platform text NOT NULL,
    purpose text,
    language text NOT NULL,
    approval_status text DEFAULT 'pending'::text NOT NULL,
    last_synced_at timestamp with time zone,
    CONSTRAINT message_templates_platform_check CHECK ((platform = ANY (ARRAY['telegram'::text, 'whatsapp'::text])))
);


--
-- Name: model_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_registry (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider text NOT NULL,
    model_name text NOT NULL,
    tier text,
    input_price_per_1m_tokens numeric,
    output_price_per_1m_tokens numeric,
    cached_input_price_per_1m_tokens numeric,
    effective_from timestamp with time zone,
    enabled boolean DEFAULT true NOT NULL,
    max_context integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: prompt_change_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_change_proposals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    current_prompt_id uuid,
    proposed_prompt text,
    proposed_examples jsonb,
    rationale text,
    source_interactions jsonb,
    evaluation_score numeric,
    status text DEFAULT 'pending'::text NOT NULL,
    approved_by text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: semantic_cache; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.semantic_cache (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    query_embedding public.vector(1536) NOT NULL,
    query_text text NOT NULL,
    language text NOT NULL,
    intent text NOT NULL,
    response_text text NOT NULL,
    routed_model text NOT NULL,
    input_tokens integer,
    output_tokens integer,
    cost_usd numeric,
    retrieved_kb_ids jsonb,
    hit_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: sensitive_data_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sensitive_data_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    platform_user_id text NOT NULL,
    category text,
    detector text,
    redacted_excerpt text,
    action_taken text,
    admin_notified boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: system_prompts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_prompts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    version_tag text NOT NULL,
    role_description text,
    prompt_text text NOT NULL,
    few_shot_examples jsonb,
    is_active boolean DEFAULT false NOT NULL,
    created_by text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    prompt_type text NOT NULL,
    CONSTRAINT system_prompts_type_check CHECK ((prompt_type = ANY (ARRAY['base'::text, 'router'::text, 'evaluator'::text, 'digest'::text, 'security'::text])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    platform_user_id text NOT NULL,
    platform text NOT NULL,
    display_name text,
    preferred_language text,
    interaction_count integer DEFAULT 0 NOT NULL,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_platform_check CHECK ((platform = ANY (ARRAY['telegram'::text, 'whatsapp'::text])))
);


--
-- Name: webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_events (
    platform_message_id text NOT NULL,
    platform text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    processed boolean DEFAULT false NOT NULL,
    processing_status text,
    error_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT webhook_events_platform_check CHECK ((platform = ANY (ARRAY['telegram'::text, 'whatsapp'::text])))
);


--
-- Name: budget_policy budget_policy_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.budget_policy
    ADD CONSTRAINT budget_policy_pkey PRIMARY KEY (id);


--
-- Name: evaluation_cases evaluation_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evaluation_cases
    ADD CONSTRAINT evaluation_cases_pkey PRIMARY KEY (id);


--
-- Name: interaction_logs interaction_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interaction_logs
    ADD CONSTRAINT interaction_logs_pkey PRIMARY KEY (id);


--
-- Name: knowledge_base knowledge_base_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.knowledge_base
    ADD CONSTRAINT knowledge_base_pkey PRIMARY KEY (id);


--
-- Name: message_templates message_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_templates
    ADD CONSTRAINT message_templates_pkey PRIMARY KEY (id);


--
-- Name: message_templates message_templates_template_name_platform_language_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_templates
    ADD CONSTRAINT message_templates_template_name_platform_language_key UNIQUE (template_name, platform, language);


--
-- Name: model_registry model_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_registry
    ADD CONSTRAINT model_registry_pkey PRIMARY KEY (id);


--
-- Name: prompt_change_proposals prompt_change_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_change_proposals
    ADD CONSTRAINT prompt_change_proposals_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: semantic_cache semantic_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.semantic_cache
    ADD CONSTRAINT semantic_cache_pkey PRIMARY KEY (id);


--
-- Name: sensitive_data_events sensitive_data_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensitive_data_events
    ADD CONSTRAINT sensitive_data_events_pkey PRIMARY KEY (id);


--
-- Name: system_prompts system_prompts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_prompts
    ADD CONSTRAINT system_prompts_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (platform_user_id);


--
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (platform_message_id);


--
-- Name: idx_evaluation_cases_category_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_evaluation_cases_category_active ON public.evaluation_cases USING btree (category, active);


--
-- Name: idx_interaction_logs_needs_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interaction_logs_needs_review ON public.interaction_logs USING btree (needs_review) WHERE (needs_review = true);


--
-- Name: idx_interaction_logs_prompt_version; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interaction_logs_prompt_version ON public.interaction_logs USING btree (prompt_version_id);


--
-- Name: idx_interaction_logs_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_interaction_logs_user_created ON public.interaction_logs USING btree (platform_user_id, created_at);


--
-- Name: idx_knowledge_base_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_knowledge_base_category ON public.knowledge_base USING btree (category);


--
-- Name: idx_knowledge_base_embedding_hnsw; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_knowledge_base_embedding_hnsw ON public.knowledge_base USING hnsw (embedding public.vector_cosine_ops);


--
-- Name: idx_model_registry_tier_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_model_registry_tier_enabled ON public.model_registry USING btree (tier, enabled);


--
-- Name: idx_prompt_change_proposals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prompt_change_proposals_status ON public.prompt_change_proposals USING btree (status);


--
-- Name: idx_semantic_cache_embedding_hnsw; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_semantic_cache_embedding_hnsw ON public.semantic_cache USING hnsw (query_embedding public.vector_cosine_ops);


--
-- Name: idx_semantic_cache_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_semantic_cache_expires ON public.semantic_cache USING btree (expires_at);


--
-- Name: idx_sensitive_data_events_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sensitive_data_events_user_created ON public.sensitive_data_events USING btree (platform_user_id, created_at);


--
-- Name: idx_system_prompts_one_active_per_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_system_prompts_one_active_per_type ON public.system_prompts USING btree (prompt_type) WHERE (is_active = true);


--
-- Name: idx_users_platform; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_platform ON public.users USING btree (platform);


--
-- Name: idx_webhook_events_processing_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_processing_status ON public.webhook_events USING btree (processing_status);


--
-- Name: budget_policy trg_budget_policy_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_budget_policy_updated_at BEFORE UPDATE ON public.budget_policy FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: knowledge_base trg_knowledge_base_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_knowledge_base_updated_at BEFORE UPDATE ON public.knowledge_base FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: users trg_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: interaction_logs interaction_logs_platform_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interaction_logs
    ADD CONSTRAINT interaction_logs_platform_user_id_fkey FOREIGN KEY (platform_user_id) REFERENCES public.users(platform_user_id);


--
-- Name: interaction_logs interaction_logs_prompt_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.interaction_logs
    ADD CONSTRAINT interaction_logs_prompt_version_id_fkey FOREIGN KEY (prompt_version_id) REFERENCES public.system_prompts(id);


--
-- Name: prompt_change_proposals prompt_change_proposals_current_prompt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_change_proposals
    ADD CONSTRAINT prompt_change_proposals_current_prompt_id_fkey FOREIGN KEY (current_prompt_id) REFERENCES public.system_prompts(id);


--
-- Name: sensitive_data_events sensitive_data_events_platform_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sensitive_data_events
    ADD CONSTRAINT sensitive_data_events_platform_user_id_fkey FOREIGN KEY (platform_user_id) REFERENCES public.users(platform_user_id);


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('20260814190001'),
    ('20260814190002'),
    ('20260814190003'),
    ('20260814190004'),
    ('20260814190005'),
    ('20260814190006'),
    ('20260814190007'),
    ('20260814190008'),
    ('20260814190009'),
    ('20260814190010'),
    ('20260814190011'),
    ('20260814190012'),
    ('20260814190013'),
    ('20260815120000'),
    ('20260815140000'),
    ('20260815140001'),
    ('20260815160000');
