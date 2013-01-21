#
# requires two variables - :subject and :delegate
#
shared_examples_for 'a transparent proxy' do
  it 'should forward non-standard methods' do
    delegate.should_receive(:blahblah)
    subject.blahblah
  end

  it 'should forward standard methods' do
    delegate.should_receive(:class).and_return(73)
    subject.class.should == 73
  end

  it 'should forward methods defined on underlying Future' do
    methods = [:value, :wait, :ready?, :add_observer]
    methods.each {|meth| delegate.should_receive meth }
    methods.each {|meth| subject.send meth }
  end
end
