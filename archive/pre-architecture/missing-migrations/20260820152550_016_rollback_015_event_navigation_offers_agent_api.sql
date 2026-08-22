drop function if exists api.session_context(text);
drop function if exists api.route_to_location(text,text,text,boolean);
drop function if exists api.find_location(text,text);
drop function if exists api.event_guide(text);

drop table if exists concierge.integration_events;
drop table if exists mind.route_edges;
drop table if exists mind.exhibitors;
drop table if exists mind.offers;
drop table if exists mind.organization_content;

drop index if exists mind.locations_name_trgm_idx;
drop index if exists mind.locations_event_type_idx;
drop index if exists mind.locations_parent_idx;
drop index if exists mind.locations_event_slug_uq;

alter table mind.locations
  drop column if exists active,
  drop column if exists accessibility,
  drop column if exists map_coordinates,
  drop column if exists floor_label,
  drop column if exists description,
  drop column if exists aliases,
  drop column if exists slug,
  drop column if exists parent_id;
