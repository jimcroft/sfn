require 'digest/sha2'

module KnifeCloudformation
  class Cache

    class << self

      def configure(type, args={})
        type = type.to_sym
        case type
        when :redis
          require 'redis-objects'
          Redis::Objects.redis = Redis.new(args)
        when :local
        else
          raise TypeError.new("Unsupported caching type: #{type}")
        end
        enable(type)
      end

      def enable(type)
        @type = type.to_sym
      end

      def type
        @type || :local
      end

    end

    attr_reader :key
    attr_reader :direct_store

    def initialize(key)
      if(key.respond_to?(:sort))
        key = key.sort
      end
      @key = Digest::SHA256.hexdigest(key.to_s)
      @direct_store = {}
    end

    def init(name, kind)
      name = name.to_sym
      unless(@direct_store[name])
        full_name = [key, name.to_s].join('_')
        @direct_store[name] = get_storage(self.class.type, kind, full_name)
      end
      true
    end

    def clear!(*args)
      internal_lock do
        args = @direct_store.keys if args.empty?
        args.each do |key|
          value = @direct_store[key]
          if(value.respond_to?(:clear))
            value.clear
          elsif(value.respond_to?(:value))
            value.value = nil
          end
        end
        yield if block_given?
      end
      true
    end

    def get_storage(store_type, data_type, full_name, args={})
      case store_type
      when :redis
        get_redis_storage(data_type, full_name, args)
      when :local
        get_local_storage(data_type, full_name, args)
      else
        raise TypeError.new("Unsupported caching storage type encountered: #{store_type}")
      end
    end

    def get_redis_storage(data_type, full_name, args={})
      case data_type
      when :array
        Redis::List.new(full_name, {:marshal => true}.merge(args))
      when :hash
        Redis::HashKey.new(full_name)
      when :value
        Redis::Value.new(full_name, {:marshal => true}.merge(args))
      when :lock
        Redis::Lock.new(full_name, {:expiration => 3, :timeout => 0.1}.merge(args))
      else
        raise TypeError.new("Unsupported caching data type encountered: #{data_type}")
      end
    end

    def get_local_storage(data_type, full_name, args={})
      case data_type
      when :array
        []
      when :hash
        {}
      when :value
        LocalValue.new
      when :lock
        LocalLock.new
      else
        raise TypeError.new("Unsupported caching data type encountered: #{data_type}")
      end
    end

    class LocalValue
      attr_accessor :value
      def initialize(*args)
        @value = nil
      end
    end

    class LocalLock
      def initialize(*args)
      end

      def lock
        yield
      end

      def clear
      end
    end

    def internal_lock
      get_storage(self.class.type, :lock, :internal_access, :timeout => 20).lock do
        yield
      end
    end

    def [](name)
      internal_lock do
        @direct_store[name.to_sym]
      end
    end

    def []=(key, val)
      raise 'Setting backend data is not allowed'
    end

  end
end