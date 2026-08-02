import { render } from '@testing-library/react-native';

import App from '../App';

// T2 은 검사 도구가 실제로 도는지만 확인한다. 화면 문구는 T10/T11 에서 바뀌므로 붙잡지 않는다.
// RTL 14 의 render 는 Promise 를 돌려준다. await 를 빠뜨리면 조용히 undefined 가 된다.
it('App 이 렌더된다', async () => {
  const tree = await render(<App />);
  expect(tree.toJSON()).toBeTruthy();
});
