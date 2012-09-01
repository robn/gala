//  
//  Copyright (C) 2012 Tom Beckmann, Rico Tzschichholz
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

using Meta;
using Clutter;

namespace Gala
{
	public class WorkspaceThumb : Clutter.Actor
	{
		
		//target for DnD
		internal static Actor? destination = null;
		
		static const int INDICATOR_BORDER = 5;
		internal static const int APP_ICON_SIZE = 32;
		static const float THUMBNAIL_HEIGHT = 80.0f;
		static const uint CLOSE_BUTTON_DELAY = 500;
		
		public signal void clicked ();
		public signal void closed ();
		public signal void window_on_last ();
		
		public unowned Workspace? workspace { get; set; }
		
		unowned Screen screen;
		
		static GtkClutter.Texture? plus = null;
		
		Gtk.StyleContext selector_style;
		
		internal Clone wallpaper;
		Clutter.Actor windows;
		internal Clutter.Actor icons;
		Actor indicator;
		GtkClutter.Texture close_button;
		
		uint hover_timer = 0;
		
		public WorkspaceThumb (Workspace _workspace)
		{
			workspace = _workspace;
			screen = workspace.get_screen ();
			
			var e = new Gtk.EventBox ();
			e.show ();
			selector_style = e.get_style_context ();
			selector_style.add_class ("gala-workspace-selected");
			selector_style.add_provider (Utils.get_default_style (), Gtk.STYLE_PROVIDER_PRIORITY_FALLBACK);
			
			screen.workspace_switched.connect (handle_workspace_switched);
			screen.workspace_added.connect (workspace_added);
			
			workspace.window_added.connect (handle_window_added);
			workspace.window_removed.connect (handle_window_removed);
			
			int swidth, sheight;
			screen.get_size (out swidth, out sheight);
			
			var width = Math.floorf ((THUMBNAIL_HEIGHT / sheight) * swidth);
			
			reactive = true;
			
			indicator = new Actor ();
			indicator.width = width + 2 * INDICATOR_BORDER;
			indicator.height = THUMBNAIL_HEIGHT + 2 * INDICATOR_BORDER;
			indicator.opacity = 0;
			indicator.content = new Canvas ();
			(indicator.content as Canvas).draw.connect (draw_indicator);
			(indicator.content as Canvas).set_size ((int)indicator.width, (int)indicator.height);
			
			handle_workspace_switched (-1, screen.get_active_workspace_index (), MotionDirection.LEFT);
			
			// FIXME find a nice way to draw a border around it, maybe combinable with the indicator using a ShaderEffect
			wallpaper = new Clone (Compositor.get_background_actor_for_screen (screen));
			wallpaper.x = INDICATOR_BORDER;
			wallpaper.y = INDICATOR_BORDER;
			wallpaper.height = THUMBNAIL_HEIGHT;
			wallpaper.width = width;
			
			close_button = new GtkClutter.Texture ();
			try {
				close_button.set_from_pixbuf (Granite.Widgets.Utils.get_close_pixbuf ());
			} catch (Error e) { warning (e.message); }
			close_button.x = -12.0f;
			close_button.y = -10.0f;
			close_button.reactive = true;
			close_button.scale_gravity = Clutter.Gravity.CENTER;
			close_button.scale_x = 0;
			close_button.scale_y = 0;
			
			icons = new Actor ();
			icons.layout_manager = new BoxLayout ();
			(icons.layout_manager as Clutter.BoxLayout).spacing = 6;
			icons.height = APP_ICON_SIZE;
			
			windows = new Actor ();
			windows.x = INDICATOR_BORDER;
			windows.y = INDICATOR_BORDER;
			windows.height = THUMBNAIL_HEIGHT;
			windows.width = width;
			windows.clip_to_allocation = true;
			
			add_child (indicator);
			add_child (wallpaper);
			add_child (windows);
			add_child (icons);
			add_child (close_button);
			
			//kill the workspace
			close_button.button_release_event.connect (close_workspace);
			
			if (plus == null) {
				var css = new Gtk.CssProvider ();
				var img = new Gtk.Image ();
				try {
					css.load_from_data ("*{text-shadow:0 1 #f00;color:alpha(#fff, 0.8);}", -1);
				} catch (Error e) { warning(e.message); }
				img.get_style_context ().add_provider (css, 20000);
				
				plus = new GtkClutter.Texture ();
				try {
					var pix = Gtk.IconTheme.get_default ().choose_icon ({"list-add-symbolic", "list-add"}, (int)THUMBNAIL_HEIGHT / 2, 0).
						load_symbolic_for_context (img.get_style_context ());
					plus.set_from_pixbuf (pix);
				} catch (Error e) { warning (e.message); }
				
				plus.x = wallpaper.x + wallpaper.width / 2 - plus.width / 2;
				plus.y = wallpaper.y + wallpaper.height / 2 - plus.height / 2;
			}
			
			add_action_with_name ("drop", new DropAction ());
			(get_action ("drop") as DropAction).over_in.connect (over_in);
			(get_action ("drop") as DropAction).over_out.connect (over_out);
			(get_action ("drop") as DropAction).drop.connect (drop);
			
			check_last_workspace ();
			
			visible = false;
		}
		
		void over_in (Actor actor)
		{
			if (indicator.opacity != 255)
				indicator.animate (AnimationMode.LINEAR, 100, opacity:200);
		}
		void over_out (Actor actor)
		{
			if (indicator.opacity != 255)
				indicator.animate (AnimationMode.LINEAR, 100, opacity:0);
			
			//when draggin, the leave event isn't emitted
			if (close_button.visible)
				hide_close_button ();
		}
		void drop (Actor actor, float x, float y)
		{
			float ax, ay;
			actor.transform_stage_point (x, y, out ax, out ay);
			
			destination = actor;
			
			if (indicator.opacity != 255)
				indicator.animate (AnimationMode.LINEAR, 100, opacity:0);
		}
		
		~WorkspaceThumb ()
		{
			screen.workspace_switched.disconnect (handle_workspace_switched);
			screen.workspace_added.disconnect (workspace_added);
		}
		
		bool close_workspace (Clutter.ButtonEvent event)
		{
			workspace.list_windows ().foreach ((w) => {
				if (w.window_type != WindowType.DOCK) {
					w.delete (event.time);
				}
			});
			
			GLib.Timeout.add (250, () => {
				//wait for confirmation dialogs to popup
				if (Utils.get_n_windows (workspace) == 0) {
					workspace.window_added.disconnect (handle_window_added);
					workspace.window_removed.disconnect (handle_window_removed);
					
					animate (Clutter.AnimationMode.LINEAR, 250, width : 0.0f, opacity : 0);
					
					closed ();
				} else
					workspace.activate (workspace.get_screen ().get_display ().get_current_time ());
				
				return false;
			});
			
			return true;
		}
		
		bool draw_indicator (Cairo.Context cr)
		{
			cr.set_operator (Cairo.Operator.CLEAR);
			cr.paint ();
			cr.set_operator (Cairo.Operator.OVER);
			
			selector_style.render_background (cr, 0, 0, indicator.width, indicator.height);
			selector_style.render_frame (cr, 0, 0, indicator.width, indicator.height);
			
			return false;
		}
		
		void workspace_added (int index)
		{
			check_last_workspace ();
		}
		
		void update_windows ()
		{
			windows.remove_all_children ();
			
			if (workspace == null)
				return;
			
			int swidth, sheight;
			screen.get_size (out swidth, out sheight);
			
			// add window thumbnails
			var aspect = windows.width / swidth;
			foreach (var window in Compositor.get_window_actors (screen)) {
				if (window == null)
					continue;
				var meta_window = window.get_meta_window ();
				if (meta_window == null)
					continue;
				var type = meta_window.window_type;
				
				if ((!(window.get_workspace () == workspace.index ()) && 
					!meta_window.is_on_all_workspaces ()) ||
					meta_window.minimized ||
					(type != WindowType.NORMAL && 
					type != WindowType.DIALOG &&
					type != WindowType.MODAL_DIALOG))
					return;
				
				var clone = new Clone (window.get_texture ());
				clone.width = aspect * clone.width;
				clone.height = aspect * clone.height;
				clone.x = aspect * window.x;
				clone.y = aspect * window.y;
				
				windows.add_child (clone);
			}
		}
		
		void update_icons ()
		{
			icons.remove_all_children ();
			
			if (workspace == null)
				return;
			
			//show each icon only once, so log the ones added
			var shown_applications = new List<Bamf.Application> ();
			
			workspace.list_windows ().foreach ((w) => {
				if (w.window_type != Meta.WindowType.NORMAL || w.minimized)
					return;
				
				var app = Bamf.Matcher.get_default ().get_application_for_xid ((uint32)w.get_xwindow ());
				if (shown_applications.index (app) != -1)
					return;
				
				if (app != null)
					shown_applications.append (app);
				
				var icon = new AppIcon (w, app);
				
				icons.add_child (icon);
			});
			
			icons.x = Math.floorf (wallpaper.x + wallpaper.width / 2 - icons.width / 2);
			icons.y = Math.floorf (wallpaper.y + wallpaper.height - 5);
		}
		
		void check_last_workspace ()
		{
			//last workspace, show plus button and so on
			//give the last one a different style
			
			var index = screen.get_workspaces ().index (workspace);
			if (index < 0) {
				closed ();
				return;
			}
			
			if (index == screen.n_workspaces - 1) {
				wallpaper.opacity = 127;
				if (plus.get_parent () == null)
					add_child (plus);
			} else {
				wallpaper.opacity = 255;
				if (contains (plus))
					remove_child (plus);
			}
		}
		
		void handle_workspace_switched (int index_old, int index_new, Meta.MotionDirection direction)
		{
			if (index_old == index_new)
				return;
			
			if (workspace == null)
				return;
			
			if (workspace.index () == index_old)
				indicator.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 200, opacity : 0);
			else if (workspace.index () == index_new)
				indicator.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 200, opacity : 255);
		}
		
		void handle_window_added (Meta.Window window)
		{
			if (visible)
				update_windows ();
			
			if (workspace != null && workspace.index () == screen.n_workspaces - 1 && Utils.get_n_windows (workspace) > 0)
				window_on_last ();
		}
		
		void handle_window_removed (Meta.Window window)
		{
			if (visible)
				update_windows ();
			
			//dont remove workspaces when for example slingshot was closed
			if (window.window_type != WindowType.NORMAL &&
				window.window_type != WindowType.DIALOG &&
				window.window_type != WindowType.MODAL_DIALOG)
				return;
			
			if (workspace != null && Utils.get_n_windows (workspace) == 0) {
				workspace.window_added.disconnect (handle_window_added);
				workspace.window_removed.disconnect (handle_window_removed);
				
				closed ();
			}
		}
		
		public override void hide ()
		{
			base.hide ();
			
			icons.remove_all_children ();
			windows.remove_all_children ();
		}
		
		public override void show ()
		{
			check_last_workspace ();
			
			update_icons ();
			update_windows ();
			
			base.show ();
		}
		
		public override bool button_release_event (ButtonEvent event)
		{
			//if we drop something, don't instantly activate
			if (destination != null) {
				destination = null;
				return false;
			}
			
			if (workspace == null)
				return true;
			
			workspace.activate (screen.get_display ().get_current_time ());
			
			clicked ();
			
			return true;
		}
		
		public override bool enter_event (CrossingEvent event)
		{
			if (workspace == null)
				return true;
			
			if (workspace.index () == screen.n_workspaces - 1) {
				wallpaper.animate (AnimationMode.EASE_OUT_QUAD, 300, opacity : 210);
				return true;
			}
			
			//dont allow closing the tab if it's the last one used
			if (workspace.index () == 0 && screen.n_workspaces == 2)
				return false;
			
			if (hover_timer > 0)
				GLib.Source.remove (hover_timer);
			
			hover_timer = Timeout.add (CLOSE_BUTTON_DELAY, () => {
				close_button.visible = true;
				close_button.animate (AnimationMode.EASE_OUT_ELASTIC, 400, scale_x : 1.0f, scale_y : 1.0f);
				return false;
			});
			
			return true;
		}
		
		internal void hide_close_button ()
		{
			close_button.animate (AnimationMode.EASE_IN_QUAD, 400, scale_x : 0.0f, scale_y : 0.0f)
				.completed.connect (() => close_button.visible = false );
		}
		
		public override bool leave_event (CrossingEvent event)
		{
			if (contains (event.related))
				return false;
			
			if (hover_timer > 0) {
				GLib.Source.remove (hover_timer);
				hover_timer = 0;
			}
			
			if (workspace == null)
				return false;
			
			if (workspace.index () == screen.n_workspaces - 1)
				wallpaper.animate (AnimationMode.EASE_OUT_QUAD, 400, opacity : 127);
			else
				hide_close_button ();
			
			return false;
		}
	}
}