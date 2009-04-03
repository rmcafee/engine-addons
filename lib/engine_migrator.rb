module ActiveRecord
  class EngineMigrator < ActiveRecord::Migrator     
    class << self
      def migrate(migrations_path, engine_name, target_version = nil)
        case
          when target_version.nil?            then up(migrations_path, engine_name, target_version)
          when current_version(engine_name) > target_version then down(migrations_path, engine_name, target_version)
          else                                up(migrations_path, engine_name, target_version)
        end
      end

      def up(migrations_path, engine_name, target_version = nil)
        self.new(:up, migrations_path, engine_name, target_version).migrate
      end

      def down(migrations_path, engine_name, target_version = nil)
        self.new(:down, migrations_path, engine_name, target_version).migrate
      end

      def schema_migrations_table_name(engine_name)
        if ActiveRecord::Base::connection.table_exists?("schema_migrations_#{engine_name}")
          Base.table_name_prefix + "schema_migrations_#{engine_name}" + Base.table_name_suffix
        else
          ActiveRecord::Base::connection.create_table("schema_migrations_#{engine_name}") { |t| t.string :version, :default => 0 }
          Base.table_name_prefix + "schema_migrations_#{engine_name}" + Base.table_name_suffix
        end
      end

      def get_all_versions(engine_name)
        Base.connection.select_values("SELECT version FROM #{schema_migrations_table_name(engine_name)}").map(&:to_i).sort
      end

      def current_version(engine_name)
        sm_table = schema_migrations_table_name(engine_name)
        if Base.connection.table_exists?(sm_table)
          get_all_versions(engine_name).max || 0
        else
          0
        end
      end
    end

    def initialize(direction, migrations_path, engine_name, target_version = nil)
      raise StandardError.new("This database does not yet support migrations") unless Base.connection.supports_migrations?
      Base.connection.initialize_schema_migrations_table
      @direction, @migrations_path, @engine_name, @target_version = direction, migrations_path, engine_name, target_version      
    end

    def migrate
      current = migrations.detect { |m| m.version == current_version }
      target = migrations.detect { |m| m.version == @target_version }

      if target.nil? && !@target_version.nil? && @target_version > 0
        raise UnknownMigrationVersionError.new(@target_version)
      end

      start = up? ? 0 : (migrations.index(current) || 0)
      finish = migrations.index(target) || migrations.size - 1
      runnable = migrations[start..finish]

      # skip the last migration if we're headed down, but not ALL the way down
      runnable.pop if down? && !target.nil?

      runnable.each do |migration|
        Base.logger.info "#{@engine_name} - Migrating to #{migration.name} (#{migration.version})"

        # On our way up, we skip migrating the ones we've already migrated
        next if up? && migrated.include?(migration.version.to_i)

        # On our way down, we skip reverting the ones we've never migrated
        if down? && !migrated.include?(migration.version.to_i)
          migration.announce '#{@engine_name} - never migrated, skipping'; migration.write
          next
        end

        begin
          ddl_transaction do
            migration.migrate(@direction)
            record_version_state_after_migrating(migration.version, @engine_name)
          end
        rescue => e
          canceled_msg = Base.connection.supports_ddl_transactions? ? "this and " : ""
          raise StandardError, "#{@engine_name} - An error has occurred, #{canceled_msg}all later migrations canceled:\n\n#{e}", e.backtrace
        end
      end
    end

    def migrated
      @migrated_versions ||= self.class.get_all_versions(@engine_name)
    end

    private
      def record_version_state_after_migrating(version, engine_name)
        sm_table = self.class.schema_migrations_table_name(engine_name)

        @migrated_versions ||= []
        if down?
          @migrated_versions.delete(version.to_i)
          Base.connection.update("DELETE FROM #{sm_table} WHERE version = '#{version}'")
        else
          @migrated_versions.push(version.to_i).sort!
          Base.connection.insert("INSERT INTO #{sm_table} (version) VALUES ('#{version}')")
        end
      end
  end
end