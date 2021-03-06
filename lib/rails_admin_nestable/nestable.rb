module RailsAdmin
  module Config
    module Actions
      class Nestable < Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :breadcrumb_parent do
          parent_model = bindings[:abstract_model].try(:config).try(:parent)
          if am = parent_model && RailsAdmin.config(parent_model).try(:abstract_model)
            [:nestable, am]
          else
            [:dashboard]
          end
        end

        register_instance_option :pjax? do
          true
        end

        register_instance_option :root? do
          false
        end

        register_instance_option :collection? do
          true
        end

        register_instance_option :member? do
          false
        end

        register_instance_option :controller do
          Proc.new do |klass|
            @nestable_conf = ::RailsAdminNestable::Configuration.new @abstract_model
            @position_field = @nestable_conf.options[:position_field]
            @enable_callback = @nestable_conf.options[:enable_callback]
            @nestable_scope = @nestable_conf.options[:scope]
            @options = @nestable_conf.options
            @adapter = @abstract_model.adapter

            # Methods
            def update_tree(tree_nodes, parent_node = nil)
              tree_nodes.each do |key, value|
                model = @abstract_model.model.find(value['id'].to_s)
                model.parent = parent_node || nil
                model.send("#{@position_field}=".to_sym, (key.to_i + 1)) if @position_field.present?
                model.save!(validate: @enable_callback)
                update_tree(value['children'], model) if value.has_key?('children')
              end
            end

            def update_list(model_list)
              model_list.each do |key, value|
                model = @abstract_model.model.find(value['id'].to_s)
                model.send("#{@position_field}=".to_sym, (key.to_i + 1))
                model.save!(validate: @enable_callback)
              end
            end

            if request.post? && params['tree_nodes'].present?
              begin
                update = ->{
                  update_tree params[:tree_nodes] if @nestable_conf.tree?
                  update_list params[:tree_nodes] if @nestable_conf.list?
                }

                ActiveRecord::Base.transaction { update.call } if @adapter == :active_record
                update.call if @adapter == :mongoid
              rescue Exception => e
              end
            end

            query = list_entries(@model_config, :nestable, false, false).reorder(nil)

            case @options[:scope].class.to_s
              when 'Proc'
                query.merge!(@options[:scope].call)
              when 'Symbol'
                query.merge!(@abstract_model.model.public_send(@options[:scope]))
            end

            if @nestable_conf.tree?
              @tree_nodes = if @options[:position_field].present?
                query.arrange(order: @options[:position_field])
              else
                query.arrange
              end
            end

            if @nestable_conf.list?
              @tree_nodes = query.order("#{@options[:position_field]} ASC")
            end

	    if request.post? && params['tree_nodes'].present?
	      output = {}
	      query.each do |tree_node|
	        output[tree_node.id] = "<ul class='inline list-inline'>#{menu_for( :member, @abstract_model, tree_node, true ).to_s.html_safe}</ul>"
              end

	      render json: output.to_json, root: false
	    else
              render action: @action.template_name
            end
          end
        end

        register_instance_option :link_icon do
          'icon-move fa fa-arrows'
        end

        register_instance_option :http_methods do
          [:get, :post]
        end

        register_instance_option :visible? do
          current_model = ::RailsAdmin::Config.model(bindings[:abstract_model])
          authorized? && (current_model.nestable_tree || current_model.nestable_list)
        end
      end
    end
  end
end
